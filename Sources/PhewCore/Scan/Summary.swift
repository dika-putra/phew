import Foundation

public struct GroupSummary: Sendable, Identifiable {
    public let id: String
    public let bytes: Int64
    public let items: [Item]
}

public struct Summary: Sendable {
    public let byTier: [Tier: Int64]
    public let total: Int64
    /// What Quick clean frees: the preselected items that are ready (no data loss, heavy,
    /// opt-in or active project, nothing in use). Same number as the Quick clean button.
    public let reclaimable: Int64
    public let quickClean: [Item]
    public let groups: [GroupSummary]

    public init(_ items: [Item]) {
        var byTier: [Tier: Int64] = [:]
        for item in items { byTier[item.target.tier, default: 0] += item.bytes }
        self.byTier = byTier
        total = items.reduce(0) { $0 + $1.bytes }
        quickClean = items.filter { $0.preselected && $0.state == .ready }
        reclaimable = quickClean.reduce(0) { $0 + $1.bytes }
        var order: [String] = []
        var byGroup: [String: [Item]] = [:]
        for item in items {
            if byGroup[item.target.group] == nil { order.append(item.target.group) }
            byGroup[item.target.group, default: []].append(item)
        }
        groups = order.map { name in
            GroupSummary(id: name, bytes: byGroup[name]!.reduce(0) { $0 + $1.bytes }, items: byGroup[name]!)
        }
        .filter { $0.bytes > 0 }
        .sorted { $0.bytes > $1.bytes }
    }
}

public struct ProjectGroup: Sendable, Identifiable {
    public let id: URL
    public let info: ProjectInfo
    public let items: [Item]
    /// Items under the size limit, shown as one line (monorepos have many 8 KB .turbo folders).
    public let small: [Item]
    public let bytes: Int64
}

public func projectGroups(_ items: [Item], smallBelow: Int64 = 1_048_576) -> [ProjectGroup] {
    var order: [URL] = []
    var byRoot: [URL: [Item]] = [:]
    for item in items {
        guard let root = item.project?.root else { continue }
        if byRoot[root] == nil { order.append(root) }
        byRoot[root, default: []].append(item)
    }
    return order.map { root in
        let all = byRoot[root]!
        return ProjectGroup(id: root, info: all[0].project!, items: all.filter { $0.bytes >= smallBelow },
                            small: all.filter { $0.bytes < smallBelow }, bytes: all.reduce(0) { $0 + $1.bytes })
    }
    .sorted { $0.bytes > $1.bytes }
}
