import Foundation
import Observation
import PhewCore

enum Screen: Equatable {
    case home
    case group(String)
    case confirm(CleanPlan)
    case cleaning(String)
    case receipt(Receipt)
    case settings
}

@MainActor @Observable
final class AppModel {
    private(set) var snapshot: ScanSnapshot?
    private(set) var isScanning = false
    private(set) var available: Int64 = 0
    var screen: Screen = .home
    var selection: Set<String> = []
    private(set) var lastReceipt: Receipt?
    private var cleaning: Task<Void, Never>?

    private let scan: @Sendable () async -> ScanSnapshot
    private let cache: ScanCache
    private let availableSpace: @Sendable () -> Int64
    private let running: RunningCheck
    private let execute: @Sendable (CleanPlan, @escaping @Sendable (String) -> Void) async -> Receipt
    private let notify: @Sendable (String) -> Void
    private let alertSettings: @Sendable () -> LowSpaceAlert
    private let defaults: UserDefaults
    private let openDocker: @Sendable () async -> Void
    private let dockerScan: @Sendable () async -> DockerScan
    private let dockerPoll: Duration
    private(set) var isStartingDocker = false

    init(scan: @escaping @Sendable () async -> ScanSnapshot = AppModel.liveScan,
         cache: ScanCache = ScanCache(),
         available: @escaping @Sendable () -> Int64 = { DiskSize.available() },
         running: RunningCheck = .live,
         execute: @escaping @Sendable (CleanPlan, @escaping @Sendable (String) -> Void) async -> Receipt = {
             await Executor.live(runAdmin: { await AdminDelete.run($0) }).execute($0, progress: $1)
         },
         notify: @escaping @Sendable (String) -> Void = { Notifier.post($0) },
         alertSettings: @escaping @Sendable () -> LowSpaceAlert = { ConfigStore().load().config.lowSpaceAlert },
         defaults: UserDefaults = .standard,
         reconcile: @Sendable (ScanSnapshot) -> ScanSnapshot = AppModel.liveReconcile,
         openDocker: @escaping @Sendable () async -> Void = { _ = try? await Shell.run("/usr/bin/open", ["-a", "Docker"]) },
         dockerScan: @escaping @Sendable () async -> DockerScan = {
             await Docker.scan(home: FileManager.default.homeDirectoryForCurrentUser)
         },
         dockerPoll: Duration = .seconds(3)) {
        self.openDocker = openDocker
        self.dockerScan = dockerScan
        self.dockerPoll = dockerPoll
        self.notify = notify
        self.alertSettings = alertSettings
        self.defaults = defaults
        self.scan = scan
        self.cache = cache
        self.availableSpace = available
        self.running = running
        self.execute = execute
        snapshot = cache.load().map(reconcile)
        self.available = available()
        selection = Self.defaultSelection(snapshot?.items ?? [])
    }

    private static func defaultSelection(_ items: [Item]) -> Set<String> {
        Set(items.filter { $0.preselected && $0.state == .ready }.map(\.id))
    }

    var summary: Summary { Summary(snapshot?.items ?? []) }

    var isStale: Bool {
        guard let date = snapshot?.date else { return true }
        return Date.now.timeIntervalSince(date) > 2 * 3600
    }

    func refresh() async {
        // A scan during a clean would measure half-deleted folders and race the receipt.
        guard !isScanning, !isCleaning else { return }
        isScanning = true
        let result = await scan()
        let oldIDs = Set(snapshot?.items.map(\.id) ?? [])
        snapshot = result
        // Keep what the user ticked or unticked; only new items get the default selection.
        let newIDs = Set(result.items.map(\.id))
        selection = selection.intersection(newIDs)
            .union(Self.defaultSelection(result.items.filter { !oldIDs.contains($0.id) }))
        available = availableSpace()
        try? cache.save(result)
        isScanning = false
        checkSpace()
    }

    /// Called every 15 minutes and after each scan. Notifies once per drop below the threshold.
    func checkSpace() {
        available = availableSpace()
        let key = "lowSpaceAlertState"
        var state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LowSpaceAlertState.self, from: $0) }
            ?? LowSpaceAlertState()
        if state.shouldNotify(available: available, settings: alertSettings()) {
            let free = summary.reclaimable
            notify("Only \(bytes(available)) left." + (free > 0 ? " Phew can free about \(bytes(free))." : ""))
        }
        defaults.set(try? JSONEncoder().encode(state), forKey: key)
    }

    var isCleaning: Bool { cleaning != nil }

    func items(in group: String) -> [Item] {
        snapshot?.items.filter { $0.target.group == group } ?? []
    }

    func projectItems(_ root: URL) -> [Item] {
        snapshot?.items.filter { $0.project?.root == root } ?? []
    }

    /// Selects every cleanable item of the project, or clears them when all are selected.
    func toggleProject(_ root: URL) {
        let ids = projectItems(root).filter { $0.state != .unreadable }.map(\.id)
        if ids.allSatisfy(selection.contains) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    /// Everything that is safe to clean right now, behind the usual confirmation.
    func quickClean() {
        let items = summary.quickClean
        guard !items.isEmpty else { return }
        screen = .confirm(Planner.plan(items, running: running))
    }

    func cleanSelected(in group: String) {
        let chosen = items(in: group).filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        screen = .confirm(Planner.plan(chosen, running: running))
    }

    /// Runs in a task owned by the model, so closing the popover does not stop the clean.
    func confirm() {
        guard case .confirm(let plan) = screen, !plan.items.isEmpty, cleaning == nil else { return }
        screen = .cleaning(plan.items[0].target.title)
        cleaning = Task {
            let receipt = await execute(plan) { title in
                Task { @MainActor in if case .cleaning = self.screen { self.screen = .cleaning(title) } }
            }
            apply(receipt)
            lastReceipt = receipt
            screen = .receipt(receipt)
            cleaning = nil
        }
    }

    func waitForClean() async {
        await cleaning?.value
    }

    /// Updates the cached scan from what was measured, instead of rescanning everything.
    private func apply(_ receipt: Receipt) {
        guard var snap = snapshot else { return }
        for entry in receipt.entries where entry.skippedReason == nil {
            guard let i = snap.items.firstIndex(where: { $0.id == entry.itemID }) else { continue }
            let left = snap.items[i].bytes - entry.measured
            // No failures means the paths are gone, even when they were already gone (measured 0).
            if entry.failures.isEmpty || left <= 0 {
                snap.items.remove(at: i)
                selection.remove(entry.itemID)
            } else {
                let old = snap.items[i]
                var updated = Item(id: old.id, target: old.target, urls: old.urls, bytes: left,
                                   lastUsed: old.lastUsed, state: old.state)
                // Keep how it is cleaned: a tool item must never fall back to deleting its folder.
                updated.project = old.project
                updated.preselected = old.preselected
                updated.removal = old.removal
                updated.measure = old.measure
                updated.note = old.note
                snap.items[i] = updated
            }
        }
        snapshot = snap
        available = availableSpace()
        try? cache.save(snap)
    }

    /// Opens Docker Desktop (only when the user asks) and waits up to 90 s for it to answer,
    /// then replaces the "Docker is off" row with the Docker items.
    func startDocker() async {
        guard !isStartingDocker else { return }
        isStartingDocker = true
        defer { isStartingDocker = false }
        await openDocker()
        let tries = max(1, Int(Duration.seconds(90) / dockerPoll))
        for _ in 0..<tries {
            if case .running(let items) = await dockerScan(), var snap = snapshot {
                snap.items.removeAll { $0.id.hasPrefix("docker.") }
                snap.items += items
                snap.dockerOffBytes = nil
                snapshot = snap
                selection.formUnion(Self.defaultSelection(items))
                try? cache.save(snap)
                return
            }
            try? await Task.sleep(for: dockerPoll)
        }
    }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    nonisolated static func liveReconcile(_ snapshot: ScanSnapshot) -> ScanSnapshot {
        let loaded = ConfigStore().load()
        return snapshot.reconciled(targets: Catalog.all(custom: loaded.validTargets),
                                   projectRoots: loaded.config.projectRoots.map { URL(fileURLWithPath: $0) })
    }

    nonisolated static func liveScan() async -> ScanSnapshot {
        let loaded = ConfigStore().load()
        let targets = Catalog.all(custom: loaded.validTargets)
        let roots = loaded.config.projectRoots.map { URL(fileURLWithPath: $0) }
        async let tools = ToolScan.all(projectRoots: roots)
        var items = await TargetScanner().scan(targets, alsoOwnedBy: targets)
        var skipped = 0
        var unreadable: [URL] = []
        if !roots.isEmpty {
            let projects = await ProjectScanner(roots: roots, dormantDays: loaded.config.dormantDays).scan()
            items += projects.items
            skipped = projects.skipped.count
            unreadable = projects.unreadable
        }
        let toolResult = await tools
        items += toolResult.items
        var dockerOff: Int64?
        if case .off(let bytes) = toolResult.docker { dockerOff = bytes }
        return ScanSnapshot(date: .now, items: items, skippedProjects: skipped, unreadable: unreadable, dockerOffBytes: dockerOff)
    }
}
