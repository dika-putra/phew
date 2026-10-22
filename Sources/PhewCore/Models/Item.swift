import Foundation

public enum ItemState: Codable, Sendable, Equatable {
    case ready
    case inUse(app: String)
    case unreadable
    /// Kept on purpose (the active SDK version, a tool's default); never planned.
    case locked(String)
}

/// One step of a tool-based clean.
public enum Step: Codable, Sendable, Equatable {
    /// `[executable, args…]`, run through Shell.
    case run([String])
    /// Delete one path through the item's PathGuard.
    case remove(URL)
    /// Run until it exits 0, up to `times` tries (CoreSimulator lags after a runtime delete).
    case retry(times: Int, delaySeconds: Int, [String])
}

public enum Removal: Codable, Sendable, Equatable {
    case paths
    case steps([Step])
    case adminDyld
}

public enum Measure: Codable, Sendable, Equatable {
    case paths
    case docker
    case runtime(uuid: String)
}

public struct Item: Codable, Sendable, Identifiable, Equatable {
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
    public var removal: Removal = .paths
    public var measure: Measure = .paths
    /// Extra line under the title, for example "Used by 2 projects".
    public var note: String?

    public init(id: String, target: PathTarget, urls: [URL], bytes: Int64, lastUsed: Date?, state: ItemState) {
        self.id = id
        self.target = target
        self.urls = urls
        self.bytes = bytes
        self.lastUsed = lastUsed
        self.state = state
        self.preselected = Self.defaultSelection(target)
    }

    // Caches written before removal/measure/note existed still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        target = try c.decode(PathTarget.self, forKey: .target)
        urls = try c.decode([URL].self, forKey: .urls)
        bytes = try c.decode(Int64.self, forKey: .bytes)
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed)
        state = try c.decode(ItemState.self, forKey: .state)
        preselected = try c.decode(Bool.self, forKey: .preselected)
        project = try c.decodeIfPresent(ProjectInfo.self, forKey: .project)
        removal = try c.decodeIfPresent(Removal.self, forKey: .removal) ?? .paths
        measure = try c.decodeIfPresent(Measure.self, forKey: .measure) ?? .paths
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    static func defaultSelection(_ target: PathTarget) -> Bool {
        target.tier != .dataLoss && target.flags.isDisjoint(with: [.heavy, .needsAdmin, .optIn])
    }
}

public struct ProjectInfo: Codable, Sendable, Equatable {
    public let root: URL
    public let name: String
    public let stacks: [String]
    public let lastModified: Date?
    public let dormant: Bool
}
