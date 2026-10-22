import Foundation

public struct ConfigIssue: Sendable, Equatable {
    public let message: String
}

public enum ConfigError: Error, Equatable {
    case protectedRoot(String)
}

private struct RawTargets: Decodable {
    let customTargets: [Lossy<CustomTargetSpec>]?
}

public struct ConfigStore: Sendable {
    public let url: URL
    public let home: URL

    public init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/phew/config.json"),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.url = url
        self.home = home
    }

    /// Never rewrites an existing file: a file that does not parse is left for the user to fix.
    public func load() -> (config: PhewConfig, validTargets: [CustomTargetSpec], issues: [ConfigIssue]) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let config = PhewConfig()
            do {
                try save(config)
                return (config, [], [])
            } catch {
                return (config, [], [ConfigIssue(message: "Could not create \(url.path): \(error.localizedDescription)")])
            }
        }
        let config: PhewConfig
        do {
            config = try JSONDecoder().decode(PhewConfig.self, from: Data(contentsOf: url))
        } catch {
            return (PhewConfig(), [], [ConfigIssue(message: "\(url.path) is not valid, using defaults: \(error.localizedDescription)")])
        }
        var valid: [CustomTargetSpec] = []
        var issues: [ConfigIssue] = []
        let raw = (try? JSONDecoder().decode(RawTargets.self, from: Data(contentsOf: url)))?.customTargets ?? []
        for (index, entry) in raw.enumerated() where entry.value == nil {
            issues.append(ConfigIssue(message: "Custom target #\(index + 1) skipped: \(entry.error ?? "invalid entry")"))
        }
        for target in config.customTargets {
            if let problem = problem(with: target) {
                issues.append(ConfigIssue(message: "Custom target \"\(target.id)\" skipped: \(problem)"))
            } else {
                valid.append(target)
            }
        }
        return (config, valid, issues)
    }

    public func save(_ config: PhewConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(config).write(to: url, options: .atomic)
    }

    /// Stores the real path, so a root that is a symlink (for example to another volume) is
    /// judged by where it points.
    public func addProjectRoot(_ root: URL) throws {
        let realURL = root.standardizedFileURL.resolvingSymlinksInPath()
        if PathGuard.isForbidden(realURL, home: home) { throw ConfigError.protectedRoot(realURL.path) }
        // Decode directly (throws on a malformed file) so a broken file is never replaced by defaults.
        var config = FileManager.default.fileExists(atPath: url.path)
            ? try JSONDecoder().decode(PhewConfig.self, from: Data(contentsOf: url))
            : PhewConfig()
        let real = realURL.path
        guard !config.projectRoots.contains(real) else { return }
        config.projectRoots.append(real)
        try save(config)
    }

    /// Changes settings and saves. A file that does not parse is left alone (throws).
    public func update(_ change: (inout PhewConfig) -> Void) throws {
        var config = FileManager.default.fileExists(atPath: url.path)
            ? try JSONDecoder().decode(PhewConfig.self, from: Data(contentsOf: url))
            : PhewConfig()
        change(&config)
        try save(config)
    }

    public func removeProjectRoot(_ root: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var config = try JSONDecoder().decode(PhewConfig.self, from: Data(contentsOf: url))
        let real = root.standardizedFileURL.resolvingSymlinksInPath().path
        config.projectRoots.removeAll { $0 == real || $0 == root.standardizedFileURL.path }
        try save(config)
    }

    private func problem(with target: CustomTargetSpec) -> String? {
        if !target.id.hasPrefix("custom.") { return "id must start with \"custom.\"" }
        if target.paths.isEmpty { return "no paths" }
        for path in target.paths {
            guard path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") else { return "path \"\(path)\" must start with / or ~/" }
            let url = expandTilde(path, home: home)
            if PathGuard.isForbidden(url, home: home) || PathGuard.isForbidden(url.resolvingSymlinksInPath(), home: home) {
                return "path \"\(path)\" is protected"
            }
            // Custom targets are ticked by default and join Quick clean: only inside home,
            // and never in ~/.config (tokens, Phew's own config).
            for candidate in [url, url.resolvingSymlinksInPath()] {
                let c = candidate.standardizedFileURL.pathComponents.map { $0.lowercased() }
                let h = home.standardizedFileURL.pathComponents.map { $0.lowercased() }
                if !c.starts(with: h) { return "path \"\(path)\" must be inside your home folder" }
                if c.count > h.count, c[h.count] == ".config" { return "path \"\(path)\" is protected" }
            }
        }
        return nil
    }
}
