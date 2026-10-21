import Foundation

public struct ScanSnapshot: Codable, Sendable, Equatable {
    public var date: Date
    public var items: [Item]
    public var skippedProjects: Int
    public var unreadable: [URL]

    public init(date: Date, items: [Item], skippedProjects: Int, unreadable: [URL]) {
        self.date = date
        self.items = items
        self.skippedProjects = skippedProjects
        self.unreadable = unreadable
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
