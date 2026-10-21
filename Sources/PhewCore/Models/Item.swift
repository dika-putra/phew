import Foundation

public enum ItemState: Sendable, Equatable {
    case ready
    case inUse(app: String)
    case unreadable
}

public struct Item: Sendable, Identifiable, Equatable {
    public let id: String
    public let target: PathTarget
    /// What gets deleted: the target's paths, or for a `contents` target their children.
    public let urls: [URL]
    public let bytes: Int64
    public let lastUsed: Date?
    public let state: ItemState
    public var preselected: Bool
    /// Set for build and dependency folders found by the project scanner.
    public var project: ProjectInfo?

    public init(id: String, target: PathTarget, urls: [URL], bytes: Int64, lastUsed: Date?, state: ItemState) {
        self.id = id
        self.target = target
        self.urls = urls
        self.bytes = bytes
        self.lastUsed = lastUsed
        self.state = state
        self.preselected = Self.defaultSelection(target)
    }

    static func defaultSelection(_ target: PathTarget) -> Bool {
        target.tier != .dataLoss && target.flags.isDisjoint(with: [.heavy, .needsAdmin, .optIn])
    }
}

public struct ProjectInfo: Sendable, Equatable {
    public let root: URL
    public let name: String
    public let stacks: [String]
    public let lastModified: Date?
    public let dormant: Bool
}
