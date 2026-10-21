public struct SkippedItem: Sendable, Equatable {
    public let item: Item
    public let reason: String
}

public struct CleanPlan: Sendable {
    public let items: [Item]
    public let skipped: [SkippedItem]
    public let expectedBytes: Int64
    public let hasDataLoss: Bool
    public let needsAdmin: Bool
}

public enum Planner {
    /// Rechecks running apps because the scan result may be old.
    public static func plan(_ selected: [Item], running: RunningCheck) -> CleanPlan {
        var items: [Item] = []
        var skipped: [SkippedItem] = []
        for item in selected {
            if let reason = skipReason(item, running: running) {
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
    static func skipReason(_ item: Item, running: RunningCheck) -> String? {
        if let app = running.firstRunning(item.target.skipIfRunning) {
            return inUseMessage(app: app, title: item.target.title)
        }
        // Project items carry the dev process found at scan time in their state.
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
