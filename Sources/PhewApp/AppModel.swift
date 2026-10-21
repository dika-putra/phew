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

    private let scan: @Sendable () async -> ScanSnapshot
    private let cache: ScanCache
    private let availableSpace: @Sendable () -> Int64

    init(scan: @escaping @Sendable () async -> ScanSnapshot = AppModel.liveScan,
         cache: ScanCache = ScanCache(),
         available: @escaping @Sendable () -> Int64 = { DiskSize.available() }) {
        self.scan = scan
        self.cache = cache
        self.availableSpace = available
        snapshot = cache.load()
        self.available = available()
        selection = Set(snapshot?.items.filter(\.preselected).map(\.id) ?? [])
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
        selection = Set(result.items.filter(\.preselected).map(\.id))
        available = availableSpace()
        try? cache.save(result)
        isScanning = false
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
