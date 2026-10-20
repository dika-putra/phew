import Foundation

public struct ConfigIssue: Sendable, Equatable {
    public let message: String
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
        var config = load().config
        let real = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard !config.projectRoots.contains(real) else { return }
        config.projectRoots.append(real)
        try save(config)
    }

    private func problem(with target: CustomTargetSpec) -> String? {
        if !target.id.hasPrefix("custom.") { return "id must start with \"custom.\"" }
        if target.paths.isEmpty { return "no paths" }
        for path in target.paths {
            guard path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") else { return "path \"\(path)\" must start with / or ~/" }
            if PathGuard.isForbidden(expandTilde(path, home: home), home: home) { return "path \"\(path)\" is protected" }
        }
        return nil
    }
}
