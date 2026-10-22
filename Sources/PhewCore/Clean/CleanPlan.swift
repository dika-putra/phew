public struct SkippedItem: Sendable, Equatable {
    public let item: Item
    public let reason: String
}

public struct CleanPlan: Sendable, Equatable {
    public let items: [Item]
    public let skipped: [SkippedItem]
    public let expectedBytes: Int64
    public let hasDataLoss: Bool
    public let needsAdmin: Bool
}

public enum Planner {
    /// Rechecks running apps because the scan result may be old.
    /// `devProcesses` is checked now for project items: the state from the scan may be hours old.
    public static func plan(_ selected: [Item], running: RunningCheck, devProcesses: DevProcessCheck = .live) -> CleanPlan {
        let dev = selected.contains { $0.project != nil } ? devProcesses.snapshot() : nil
        var items: [Item] = []
        var skipped: [SkippedItem] = []
        for item in selected {
            if let reason = skipReason(item, running: running, dev: dev) {
                skipped.append(SkippedItem(item: item, reason: reason))
            } else {
                items.append(item)
            }
        }
        return CleanPlan(
            items: items,
            skipped: skipped,
            expectedBytes: items.reduce(0) { $0 + $1.bytes },
            hasDataLoss: items.contains { $0.target.tier == .dataLoss },
            needsAdmin: items.contains { $0.target.flags.contains(.needsAdmin) }
        )
    }

    /// Shared with Executor so the plan and the receipt show the same text.
    static func skipReason(_ item: Item, running: RunningCheck, dev: DevProcessCheck? = nil) -> String? {
        if let app = running.firstRunning(item.target.skipIfRunning) {
            return inUseMessage(app: app, title: item.target.title)
        }
        if let project = item.project, let dev {
            return dev.runningIn(project.root).map { inUseMessage(app: $0, title: item.target.title) }
        }
        // Without a fresh dev process check, fall back to what the scan saw.
        if item.target.skipIfRunning.isEmpty, case .inUse(let app) = item.state {
            return inUseMessage(app: app, title: item.target.title)
        }
        if item.state == .unreadable {
            return "Can't read \(item.target.title). Grant Full Disk Access or check permissions."
        }
        return nil
    }

    static func inUseMessage(app: String, title: String) -> String {
        "\(app) is running. Quit \(app) to clean \(title)."
    }
}
