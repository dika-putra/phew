import Foundation

public struct ToolScanResult: Sendable {
    public let items: [Item]
    public let docker: DockerScan
}

/// Everything that needs a tool to measure or clean, scanned concurrently (each tool lookup
/// starts a login shell, about a second each).
public enum ToolScan {
    public static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser, projectRoots: [URL],
                           run: @escaping @Sendable ([String]) async -> ShellResult? = liveRun) async -> ToolScanResult {
        async let caches = PackageCaches.items(home: home, run: run)
        async let docker = Docker.scan(home: home, run: run)
        async let simulators = Simulators.items(run: run)
        async let versions = Versions.items(home: home, pins: PinFinder.find(roots: projectRoots), run: run)
        let d = await docker
        var items = await caches + simulators + versions
        if case .running(let dockerItems) = d { items += dockerItems }
        return ToolScanResult(items: items, docker: d)
    }

    static let prefixes = ["npm", "pnpm", "go.modcache", "cargo.registry", "docker.", "ios.simulators", "ios.runtimes:",
                           "ios.dyld:", "fvm:", "nvm:", "rustup:"]

    public static func isToolItem(_ id: String) -> Bool {
        prefixes.contains { id == $0 || ($0.hasSuffix(":") || $0.hasSuffix(".")) && id.hasPrefix($0) }
    }
}
