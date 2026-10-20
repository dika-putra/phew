import Foundation

/// `phew scan --json` output. Bump `version` when a key changes meaning or goes away.
public func scanJSON(_ items: [Item], available: Int64) throws -> Data {
    let iso = ISO8601DateFormatter()
    let list: [[String: Any]] = items.map { item in
        let state: String = switch item.state {
        case .ready: "ready"
        case .inUse: "inUse"
        case .unreadable: "unreadable"
        }
        return [
            "id": item.id,
            "group": item.target.group,
            "title": item.target.title,
            "tier": item.target.tier.rawValue,
            "flags": item.target.flags.map(\.rawValue).sorted(),
            "bytes": item.bytes,
            "lastUsed": item.lastUsed.map { iso.string(from: $0) } ?? NSNull(),
            "state": state,
            "preselected": item.preselected,
            "paths": item.target.paths,
        ]
    }
    let root: [String: Any] = ["version": 1, "available": available, "items": list]
    return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}
