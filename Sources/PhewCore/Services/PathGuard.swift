import Foundation

public enum PathGuardError: Error, Equatable {
    case forbidden(String)
    case outsideRoots(String)
    case escapesRoot(String)
    case missingParent(String)
}

/// Last check before anything is deleted. A path must sit inside an allowed root,
/// judged by its real location (parent symlinks resolved), and never be a protected folder.
public struct PathGuard: Sendable {
    private let roots: [[String]]
    private let home: URL

    public init(allowedRoots: [URL], home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        // A root that resolves to a protected folder (a symlink to home or "/") would
        // allowlist everything below it, so it is dropped.
        self.roots = allowedRoots
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .filter { !Self.isForbidden($0, home: home) }
            .map(\.pathComponents)
        self.home = home
    }

    public func check(_ url: URL) throws(PathGuardError) {
        let path = url.standardizedFileURL
        // resolvingSymlinksInPath leaves a missing path unresolved, so a missing parent fails closed.
        guard FileManager.default.fileExists(atPath: path.deletingLastPathComponent().path) else {
            throw .missingParent(path.path)
        }
        // The last component is not resolved: deleting a symlink removes the link, not its target.
        let real = path.deletingLastPathComponent().resolvingSymlinksInPath()
            .appending(path: path.lastPathComponent)
        if Self.isForbidden(path, home: home) || Self.isForbidden(real, home: home) {
            throw .forbidden(path.path)
        }
        if isInsideRoot(real) { return }
        throw isInsideRoot(path) ? .escapesRoot(path.path) : .outsideRoots(path.path)
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let c = url.pathComponents
        return roots.contains { c.starts(with: $0) }
    }

    public static func isForbidden(_ url: URL, home: URL) -> Bool {
        // Lowercased because APFS is usually case-insensitive: "/USERS" is "/Users".
        let c = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        let h = home.standardizedFileURL.pathComponents.map { $0.lowercased() }
        if h.starts(with: c) { return true } // "/", home, or an ancestor
        if c.starts(with: ["/", "system"]) { return true }
        if c.starts(with: ["/", "library"]) {
            return !c.starts(with: ["/", "library", "developer", "coresimulator", "caches"])
        }
        return false
    }
}
