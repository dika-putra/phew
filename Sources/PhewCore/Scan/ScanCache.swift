import Foundation

public struct ScanSnapshot: Codable, Sendable, Equatable {
    public var date: Date
    public var items: [Item]
    public var skippedProjects: Int
    public var unreadable: [URL]
    /// Set when Docker Desktop is installed but not running: the size of its disk image.
    public var dockerOffBytes: Int64?

    public init(date: Date, items: [Item], skippedProjects: Int, unreadable: [URL], dockerOffBytes: Int64? = nil) {
        self.date = date
        self.items = items
        self.skippedProjects = skippedProjects
        self.unreadable = unreadable
        self.dockerOffBytes = dockerOffBytes
    }
}

/// Last scan on disk, so the popover has numbers right after launch.
public struct ScanCache: Sendable {
    public let url: URL

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Caches/com.dikaputra.phew/scan.json")) {
        self.url = url
    }

    public func load() -> ScanSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ScanSnapshot.self, from: data)
    }

    public func save(_ snapshot: ScanSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}

extension ScanSnapshot {
    /// Brings a cached scan in line with the current catalog and config: targets are replaced by
    /// their current definition (tier, paths), and items whose target or project folder is gone
    /// are dropped. A cached copy must never decide what gets deleted with an old definition.
    public func reconciled(targets: [PathTarget], projectRoots: [URL]) -> ScanSnapshot {
        let byID = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let roots = projectRoots.map { $0.standardizedFileURL.pathComponents }
        var copy = self
        copy.items = items.compactMap { item in
            if let project = item.project {
                let c = project.root.standardizedFileURL.pathComponents
                return roots.contains { c.starts(with: $0) } ? item : nil
            }
            // Tool items (versions, caches cleaned by a command) come from the tools, not the catalog.
            if ToolScan.isToolItem(item.id) { return item }
            guard let target = byID[item.id] else { return nil }
            var updated = Item(id: item.id, target: target, urls: item.urls, bytes: item.bytes,
                               lastUsed: item.lastUsed, state: item.state)
            updated.project = item.project
            return updated
        }
        return copy
    }
}
