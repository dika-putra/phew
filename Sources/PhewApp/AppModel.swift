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
    var screen: Screen = .home {
        didSet { inlineMessage = nil }
    }
    var selection: Set<String> = []
    /// Shown in the group view instead of a confirmation, for example when the app using it runs.
    var inlineMessage: String?
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

    init(scan: @escaping @Sendable () async -> ScanSnapshot = AppModel.liveScan,
         cache: ScanCache = ScanCache(),
         available: @escaping @Sendable () -> Int64 = { DiskSize.available() },
         running: RunningCheck = .live,
         execute: @escaping @Sendable (CleanPlan, @escaping @Sendable (String) -> Void) async -> Receipt = {
             await Executor().execute($0, progress: $1)
         },
         notify: @escaping @Sendable (String) -> Void = { Notifier.post($0) },
         alertSettings: @escaping @Sendable () -> LowSpaceAlert = { ConfigStore().load().config.lowSpaceAlert },
         defaults: UserDefaults = .standard) {
        self.notify = notify
        self.alertSettings = alertSettings
        self.defaults = defaults
        self.scan = scan
        self.cache = cache
        self.availableSpace = available
        self.running = running
        self.execute = execute
        snapshot = cache.load()
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
        guard !isScanning else { return }
        isScanning = true
        let result = await scan()
        snapshot = result
        selection = Self.defaultSelection(result.items)
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
            notify("Only \(bytes(available)) left. Phew can free about \(bytes(summary.reclaimable)).")
        }
        defaults.set(try? JSONEncoder().encode(state), forKey: key)
    }

    var isCleaning: Bool { cleaning != nil }

    func items(in group: String) -> [Item] {
        snapshot?.items.filter { $0.target.group == group } ?? []
    }

    func cleanItem(_ id: String) {
        guard let item = snapshot?.items.first(where: { $0.id == id }) else { return }
        let plan = Planner.plan([item], running: running)
        if plan.items.isEmpty, let reason = plan.skipped.first?.reason {
            inlineMessage = reason
            return
        }
        screen = .confirm(plan)
    }

    func projectItems(_ root: URL) -> [Item] {
        snapshot?.items.filter { $0.project?.root == root } ?? []
    }

    /// Selects every cleanable item of the project, or clears them when all are selected.
    func toggleProject(_ root: URL) {
        let ids = projectItems(root).filter { $0.state == .ready }.map(\.id)
        if ids.allSatisfy(selection.contains) { selection.subtract(ids) } else { selection.formUnion(ids) }
    }

    func cleanProject(_ root: URL) {
        let items = projectItems(root)
        guard !items.isEmpty else { return }
        let plan = Planner.plan(items, running: running)
        if plan.items.isEmpty, let reason = plan.skipped.first?.reason {
            inlineMessage = reason
            return
        }
        screen = .confirm(plan)
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
        for entry in receipt.entries where entry.skippedReason == nil && entry.measured > 0 {
            guard let i = snap.items.firstIndex(where: { $0.id == entry.itemID }) else { continue }
            let left = snap.items[i].bytes - entry.measured
            if entry.failures.isEmpty || left <= 0 {
                snap.items.remove(at: i)
                selection.remove(entry.itemID)
            } else {
                let old = snap.items[i]
                var updated = Item(id: old.id, target: old.target, urls: old.urls, bytes: left,
                                   lastUsed: old.lastUsed, state: old.state)
                updated.project = old.project
                updated.preselected = old.preselected
                snap.items[i] = updated
            }
        }
        snapshot = snap
        available = availableSpace()
        try? cache.save(snap)
    }

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    nonisolated static func liveScan() async -> ScanSnapshot {
        let loaded = ConfigStore().load()
        let targets = Catalog.all(custom: loaded.validTargets)
        var items = await TargetScanner().scan(targets, alsoOwnedBy: targets)
        var skipped = 0
        var unreadable: [URL] = []
        if !loaded.config.projectRoots.isEmpty {
            let projects = await ProjectScanner(roots: loaded.config.projectRoots.map { URL(fileURLWithPath: $0) },
                                                dormantDays: loaded.config.dormantDays).scan()
            items += projects.items
            skipped = projects.skipped.count
            unreadable = projects.unreadable
        }
        return ScanSnapshot(date: .now, items: items, skippedProjects: skipped, unreadable: unreadable)
    }
}
