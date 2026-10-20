import Foundation

public struct LowSpaceAlert: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var thresholdGB: Int

    public init(enabled: Bool, thresholdGB: Int) {
        self.enabled = enabled
        self.thresholdGB = thresholdGB
    }
}

public struct CustomTargetSpec: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var paths: [String]
    public var tier: Tier

    public init(id: String, title: String, paths: [String], tier: Tier) {
        self.id = id
        self.title = title
        self.paths = paths
        self.tier = tier
    }
}

public struct PhewConfig: Codable, Sendable, Equatable {
    public var version = 1
    public var projectRoots: [String] = []
    public var dormantDays = 14
    public var lowSpaceAlert = LowSpaceAlert(enabled: true, thresholdGB: 20)
    public var customTargets: [CustomTargetSpec] = []

    public init() {}

    // Missing keys keep their defaults, so an old or hand-edited file still loads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PhewConfig()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        projectRoots = try c.decodeIfPresent([String].self, forKey: .projectRoots) ?? d.projectRoots
        dormantDays = try c.decodeIfPresent(Int.self, forKey: .dormantDays) ?? d.dormantDays
        lowSpaceAlert = try c.decodeIfPresent(LowSpaceAlert.self, forKey: .lowSpaceAlert) ?? d.lowSpaceAlert
        customTargets = try c.decodeIfPresent([CustomTargetSpec].self, forKey: .customTargets) ?? d.customTargets
    }
}

public func expandTilde(_ path: String, home: URL) -> URL {
    if path == "~" { return home }
    if path.hasPrefix("~/") { return home.appending(path: String(path.dropFirst(2))) }
    return URL(fileURLWithPath: path)
}
