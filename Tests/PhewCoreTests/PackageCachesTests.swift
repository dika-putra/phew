import Foundation
import Testing
@testable import PhewCore

/// Stub for login-shell commands: maps the shell command text to stdout (nil = command fails).
func shellStub(_ outputs: [String: String]) -> @Sendable ([String]) async -> ShellResult? {
    { cmd in
        let text = cmd.last ?? ""
        if let out = outputs[text] { return ShellResult(status: 0, stdout: out, stderr: "") }
        return ShellResult(status: 1, stdout: "", stderr: "not found")
    }
}

@Test func npmItemWithBothFolders() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: ".npm/_cacache/a"), bytes: 4096)
        try writeFile(home.appending(path: ".npm/_npx/b"), bytes: 4096)
        let items = await PackageCaches.items(home: home, run: shellStub(["command -v npm": "/x/npm\n"]))
        let npm = try #require(items.first { $0.id == "npm" })
        #expect(npm.urls.map(\.lastPathComponent).sorted() == ["_cacache", "_npx"])
        #expect(npm.removal == .steps([.run(loginShell("npm cache clean --force")), .remove(home.appending(path: ".npm/_npx"))]))
        #expect(npm.target.tier == .redownload)
    }
}

@Test func pnpmPathFromCommand() async throws {
    try await withTempDirAsync { home in
        let store = home.appending(path: "Library/pnpm/store/v3")
        try writeFile(store.appending(path: "f"), bytes: 4096)
        let items = await PackageCaches.items(home: home, run: shellStub([
            "command -v pnpm": "/x/pnpm\n", "pnpm store path": "some banner\n\(store.path)\n"]))
        let pnpm = try #require(items.first { $0.id == "pnpm" })
        #expect(pnpm.urls.map(\.path) == [store.path])
        #expect(pnpm.removal == .steps([.run(loginShell("pnpm store prune"))]))
    }
}

@Test func toolMissingNoItem() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: ".npm/_cacache/a"), bytes: 10)
        let items = await PackageCaches.items(home: home, run: shellStub([:]))
        #expect(!items.contains { $0.id == "npm" || $0.id == "pnpm" || $0.id == "go.modcache" })
    }
}

@Test func cargoKeepsIndex() async throws {
    try await withTempDirAsync { home in
        for d in ["cache", "src", "index"] { try writeFile(home.appending(path: ".cargo/registry/\(d)/f"), bytes: 10) }
        let items = await PackageCaches.items(home: home, run: shellStub([:]))
        let cargo = try #require(items.first { $0.id == "cargo.registry" })
        #expect(cargo.urls.map(\.lastPathComponent).sorted() == ["cache", "src"])
        #expect(!cargo.urls.contains { $0.path.contains("index") })
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PHEW_REAL_TOOLS"] != nil))
func realPackageCaches() async {
    let items = await PackageCaches.items(home: FileManager.default.homeDirectoryForCurrentUser)
    for i in items { print("REAL \(i.id) \(i.bytes) \(i.urls.map(\.path))") }
    #expect(!items.isEmpty)
}
