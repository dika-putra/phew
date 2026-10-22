import Foundation
import Testing
@testable import PhewCore

private func dirs(_ home: URL, _ paths: [String]) throws {
    for p in paths { try writeFile(home.appending(path: p).appending(path: "bin/x"), bytes: 4096) }
}

/// Stub keyed by the command's last argument (the shell script text).
private func stub(_ outputs: [String: String]) -> @Sendable ([String]) async -> ShellResult? {
    { cmd in
        for (key, out) in outputs where (cmd.last ?? "").contains(key) {
            return ShellResult(status: 0, stdout: out, stderr: "")
        }
        return ShellResult(status: 1, stdout: "", stderr: "")
    }
}

@Test func nvmLocksDefault() async throws {
    try await withTempDirAsync { home in
        try dirs(home, [".nvm/versions/node/v16.20.2", ".nvm/versions/node/v24.1.0"])
        let items = await Versions.items(home: home, pins: Pins(), run: stub(["nvm version default": "v24.1.0\n"]))
        let v24 = try #require(items.first { $0.id == "nvm:v24.1.0" })
        let v16 = try #require(items.first { $0.id == "nvm:v16.20.2" })
        #expect(v24.state == .locked("nvm default"))
        #expect(v16.state == .ready && !v16.preselected)
        #expect(v16.target.title == "Node v16.20.2" && v16.target.group == "Versions")
        guard case .steps(let steps) = v16.removal, case .run(let cmd) = steps.first else { Issue.record("no step"); return }
        #expect(cmd.last?.contains("nvm uninstall 'v16.20.2'") == true)
    }
}

@Test func fvmGlobalLocked() async throws {
    try await withTempDirAsync { home in
        try dirs(home, ["fvm/versions/3.24.5", "fvm/versions/3.47.0"])
        try FileManager.default.createSymbolicLink(at: home.appending(path: "fvm/default"),
                                                   withDestinationURL: home.appending(path: "fvm/versions/3.24.5"))
        let items = await Versions.items(home: home, pins: Pins(), run: stub(["command -v fvm": "/x/fvm"]))
        #expect(items.first { $0.id == "fvm:3.24.5" }?.state == .locked("fvm global"))
        #expect(items.first { $0.id == "fvm:3.47.0" }?.state == .ready)
    }
}

@Test func rustupActiveLocked() async throws {
    try await withTempDirAsync { home in
        try dirs(home, [".rustup/toolchains/stable-aarch64-apple-darwin", ".rustup/toolchains/1.79.0-aarch64-apple-darwin"])
        let items = await Versions.items(home: home, pins: Pins(), run: stub([
            "rustup toolchain list": "stable-aarch64-apple-darwin (active, default)\n1.79.0-aarch64-apple-darwin\n"]))
        #expect(items.first { $0.id == "rustup:stable-aarch64-apple-darwin" }?.state == .locked("rustup default"))
        #expect(items.first { $0.id == "rustup:1.79.0-aarch64-apple-darwin" }?.state == .ready)
    }
}

@Test func pinnedVersionHasNote() async throws {
    try await withTempDirAsync { home in
        try dirs(home, [".nvm/versions/node/v20.11.0"])
        var pins = Pins()
        pins.node["20"] = [URL(fileURLWithPath: "/p/web"), URL(fileURLWithPath: "/p/api")]
        let items = await Versions.items(home: home, pins: pins, run: stub([:]))
        #expect(items.first?.note == "Used by api, web")
    }
}

@Test func toolMissingNoItems() async throws {
    try await withTempDirAsync { home in
        #expect(await Versions.items(home: home, pins: Pins(), run: stub([:])).isEmpty)
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PHEW_REAL_TOOLS"] != nil))
func realVersions() async {
    let roots = ConfigStore().load().config.projectRoots.map { URL(fileURLWithPath: $0) }
    let items = await Versions.items(home: FileManager.default.homeDirectoryForCurrentUser, pins: PinFinder.find(roots: roots))
    for i in items { print("REAL \(i.id) \(i.bytes / 1_000_000) MB \(i.state) \(i.note ?? "")") }
}

@Test func versionsSkipWhenAProcessUsesThem() async throws {
    try await withTempDirAsync { home in
        try dirs(home, [".nvm/versions/node/v16.20.2"])
        let items = await Versions.items(home: home, pins: Pins(), run: stub(["nvm version default": "v24.1.0\n"]))
        let v16 = try #require(items.first)
        let bin = home.appending(path: ".nvm/versions/node/v16.20.2/bin").path
        #expect(v16.target.skipIfRunning == ["env:\(bin)"])
        let running = RunningCheck(runningBundleIDs: { [:] }, processMatches: { _ in false },
                                   environmentMatches: { $0 == bin ? "zsh" : nil })
        #expect(Planner.plan([v16], running: running).skipped.first?.reason == "zsh is running. Quit zsh to clean Node v16.20.2.")
    }
}

@Test func versionInUseAtScan() async throws {
    try await withTempDirAsync { home in
        try dirs(home, [".nvm/versions/node/v16.20.2"])
        let running = RunningCheck(runningBundleIDs: { [:] }, processMatches: { _ in false }, environmentMatches: { _ in "zsh" })
        let items = await Versions.items(home: home, pins: Pins(), run: stub(["nvm version default": "v24.1.0\n"]), running: running)
        #expect(items.first?.state == .inUse(app: "zsh"))
    }
}
