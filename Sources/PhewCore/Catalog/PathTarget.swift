public struct PathTarget: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let group: String
    public let title: String
    public let tier: Tier
    public let flags: Set<Flag>
    public let paths: [String]
    /// Delete the children of each path and keep the folder itself.
    public let contents: Bool
    /// Bundle ids, or `proc:<pgrep -f pattern>` for processes without an app bundle.
    public let skipIfRunning: [String]

    public init(
        id: String, group: String, title: String, tier: Tier, flags: Set<Flag> = [],
        paths: [String], contents: Bool = false, skipIfRunning: [String] = []
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.tier = tier
        self.flags = flags
        self.paths = paths
        self.contents = contents
        self.skipIfRunning = skipIfRunning
    }
}
