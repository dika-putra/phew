import Foundation

/// Installed SDK versions from fvm, nvm and rustup, read from their folders on disk (the CLIs'
/// table output changes between releases). Removal uses each tool's own command so its
/// metadata stays right. Active and default versions are locked.
public enum Versions {
    public static func items(home: URL, pins: Pins, run: @Sendable ([String]) async -> ShellResult? = liveRun,
                             running: RunningCheck = .live) async -> [Item] {
        async let flutter = fvm(home: home, pins: pins, run: run)
        async let node = nvm(home: home, pins: pins, run: run)
        async let rust = rustup(home: home, pins: pins, run: run)
        // Show "in use" in the list already; the planner checks again before removing.
        return await (flutter + node + rust).map { item in
            guard item.state == .ready, let app = running.firstRunning(item.target.skipIfRunning) else { return item }
            var updated = Item(id: item.id, target: item.target, urls: item.urls, bytes: item.bytes,
                               lastUsed: item.lastUsed, state: .inUse(app: app))
            updated.removal = item.removal
            updated.note = item.note
            updated.preselected = false
            return updated
        }
    }

    private static func fvm(home: URL, pins: Pins, run: @Sendable ([String]) async -> ShellResult?) async -> [Item] {
        let listed = await run(loginShell("fvm list"))
        let cacheLine = listed?.stdout.split(separator: "\n").first { $0.hasPrefix("Cache directory:") }
        let folder = cacheLine.map { URL(fileURLWithPath: $0.dropFirst("Cache directory:".count).trimmingCharacters(in: .whitespaces)) }
            ?? home.appending(path: "fvm/versions")
        // fvm keeps the global version as a "default" symlink next to the versions folder.
        let global = (try? FileManager.default.destinationOfSymbolicLink(atPath: folder.deletingLastPathComponent().appending(path: "default").path))
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        return versionFolders(folder).map { dir in
            let v = dir.lastPathComponent
            return item(id: "fvm:\(v)", title: "Flutter \(v)", dir: dir,
                        state: v == global ? .locked("fvm global") : .ready,
                        users: pins.flutter[v] ?? [],
                        steps: [.run(loginShell("fvm remove \(shellQuote(v))"))])
        }
    }

    private static func nvm(home: URL, pins: Pins, run: @Sendable ([String]) async -> ShellResult?) async -> [Item] {
        let nvmDir = ProcessInfo.processInfo.environment["NVM_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appending(path: ".nvm")
        let folders = versionFolders(nvmDir.appending(path: "versions/node"))
        guard !folders.isEmpty else { return [] }
        // nvm is a shell function from nvm.sh, which login shells don't load: source it in bash.
        func nvmCommand(_ script: String) -> [String] {
            ["/bin/bash", "-c", "export NVM_DIR=\(shellQuote(nvmDir.path)); source \"$NVM_DIR/nvm.sh\" >/dev/null 2>&1; \(script)"]
        }
        let defaultVersion = lastLine(await run(nvmCommand("nvm version default")))
        return folders.map { dir in
            let v = dir.lastPathComponent
            let state: ItemState = defaultVersion == nil ? .locked("Couldn't check the nvm default")
                : v == defaultVersion ? .locked("nvm default") : .ready
            let users = pins.node.filter { nodePinMatches($0.key, v) }.flatMap(\.value)
            return item(id: "nvm:\(v)", title: "Node \(v)", dir: dir, state: state, users: Set(users),
                        steps: [.run(nvmCommand("nvm uninstall \(shellQuote(v))"))])
        }
    }

    private static func rustup(home: URL, pins: Pins, run: @Sendable ([String]) async -> ShellResult?) async -> [Item] {
        let rustupHome = ProcessInfo.processInfo.environment["RUSTUP_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appending(path: ".rustup")
        let folders = versionFolders(rustupHome.appending(path: "toolchains"))
        guard !folders.isEmpty else { return [] }
        let listed = await run(loginShell("rustup toolchain list"))
        let lines = listed?.status == 0 ? listed?.stdout.split(separator: "\n").map(String.init) : nil
        return folders.map { dir in
            let name = dir.lastPathComponent
            let line = lines?.first { $0.hasPrefix(name + " ") || $0 == name }
            let state: ItemState = lines == nil ? .locked("Couldn't check rustup")
                : line?.contains("default") == true ? .locked("rustup default")
                : line?.contains("active") == true ? .locked("Active Rust toolchain") : .ready
            // Pins name the channel ("stable", "1.79.0"); toolchain folders add the host triple.
            let users = pins.rust.filter { name == $0.key || name.hasPrefix($0.key + "-") }.flatMap(\.value)
            // "stable-aarch64-apple-darwin" -> "Rust stable"; the id keeps the full name.
            let short = ["-aarch64-apple-darwin", "-x86_64-apple-darwin"].reduce(name) { $0.replacingOccurrences(of: $1, with: "") }
            return item(id: "rustup:\(name)", title: "Rust \(short)", dir: dir, state: state, users: Set(users),
                        steps: [.run(loginShell("rustup toolchain uninstall \(shellQuote(name))"))])
        }
    }

    private static func versionFolders(_ folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && !$0.lastPathComponent.hasPrefix(".") }
            // Rebuild from `folder`: contentsOfDirectory can add /private, while PATH entries keep
            // the path as the shell wrote it ($HOME/.nvm/...), and the in-use check compares text.
            .map { folder.appending(path: $0.lastPathComponent) }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
    }

    private static func item(id: String, title: String, dir: URL, state: ItemState, users: Set<URL>, steps: [Step]) -> Item {
        // A terminal after `nvm use` (or a running flutter, cargo, node) has this bin folder on
        // PATH or runs from it: the version is in use there. Rechecked when planning and cleaning.
        let target = PathTarget(id: id, group: "Versions", title: title, tier: .redownload, flags: [.heavy], paths: [dir.path],
                                skipIfRunning: ["env:\(dir.appending(path: "bin").path)"])
        var item = Item(id: id, target: target, urls: [dir], bytes: DiskSize.allocated(dir).bytes, lastUsed: nil, state: state)
        item.removal = .steps(steps)
        if !users.isEmpty {
            let names = users.map(\.lastPathComponent).sorted()
            item.note = "Used by " + names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " and \(names.count - 3) more" : "")
        }
        return item
    }
}
