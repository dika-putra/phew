import Foundation

/// Package manager caches that are cleaned with the tool's own command.
public enum PackageCaches {
    public static func items(home: URL, run: @Sendable ([String]) async -> ShellResult? = liveRun) async -> [Item] {
        func has(_ tool: String) async -> Bool { lastLine(await run(loginShell("command -v \(tool)"))) != nil }
        func existing(_ urls: [URL]) -> [URL] { urls.filter { FileManager.default.fileExists(atPath: $0.path) } }
        var items: [Item] = []

        if await has("npm") {
            let npx = home.appending(path: ".npm/_npx")
            let urls = existing([home.appending(path: ".npm/_cacache"), npx])
            if !urls.isEmpty {
                // `npm cache clean` leaves the npx cache, so it is removed separately.
                items.append(item("npm", "Node", "npm cache", paths: ["~/.npm"], urls: urls,
                                  steps: [.run(loginShell("npm cache clean --force")), .remove(npx)]))
            }
        }
        if await has("pnpm"), let store = lastLine(await run(loginShell("pnpm store path"))) {
            let urls = existing([URL(fileURLWithPath: store)])
            if !urls.isEmpty {
                items.append(item("pnpm", "Node", "pnpm store (unused packages)", paths: [store], urls: urls,
                                  steps: [.run(loginShell("pnpm store prune"))]))
            }
        }
        if await has("go"), let cache = lastLine(await run(loginShell("go env GOMODCACHE"))) {
            let urls = existing([URL(fileURLWithPath: cache)])
            if !urls.isEmpty {
                items.append(item("go.modcache", "Go", "Go module cache", paths: [cache], urls: urls,
                                  steps: [.run(loginShell("go clean -modcache"))]))
            }
        }
        // The index stays: it is small and rebuilding it is slow.
        let registry = home.appending(path: ".cargo/registry")
        let cargo = existing([registry.appending(path: "cache"), registry.appending(path: "src")])
        if !cargo.isEmpty {
            items.append(item("cargo.registry", "Rust", "Cargo registry cache", paths: ["~/.cargo/registry"], urls: cargo,
                              steps: cargo.map { .remove($0) }))
        }
        return items
    }

    private static func item(_ id: String, _ group: String, _ title: String, paths: [String], urls: [URL],
                             steps: [Step]) -> Item {
        let target = PathTarget(id: id, group: group, title: title, tier: .redownload, paths: paths)
        var item = Item(id: id, target: target, urls: urls, bytes: DiskSize.allocated(urls).bytes,
                        lastUsed: nil, state: .ready)
        item.removal = .steps(steps)
        return item
    }
}
