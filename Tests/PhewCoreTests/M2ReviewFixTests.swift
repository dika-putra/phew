import Foundation
import Testing
@testable import PhewCore

@Test func lockedFileDeepInsideKeepsOnlyItself() async throws {
    try await withTempDirAsync { home in
        let a = home.appending(path: "a")
        try writeFile(a.appending(path: "f1"), bytes: 10)
        try writeFile(a.appending(path: "f3"), bytes: 10)
        let locked = a.appending(path: "sub/locked")
        try writeFile(locked, bytes: 10)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked.path) }
        let items = await TargetScanner(home: home, running: notRunning).scan([target("a", ["~/a"])])
        let receipt = await Executor(home: home, running: notRunning).execute(Planner.plan(items, running: notRunning))
        #expect(!FileManager.default.fileExists(atPath: a.appending(path: "f1").path))
        #expect(!FileManager.default.fileExists(atPath: a.appending(path: "f3").path))
        #expect(FileManager.default.fileExists(atPath: locked.path))
        #expect(receipt.entries[0].failures.contains { $0.hasPrefix(locked.path) })
    }
}

@Test func measuredUsesSizeRightBeforeDelete() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "a/f"), bytes: 4096)
        let t = target("a", ["~/a"])
        let stale = Item(id: "a", target: t, urls: [home.appending(path: "a")], bytes: 500_000_000,
                         lastUsed: nil, state: .ready)
        let receipt = await Executor(home: home, running: notRunning).execute(Planner.plan([stale], running: notRunning))
        #expect(receipt.entries[0].measured < 1_048_576)
    }
}

@Test func symlinkTargetRootIsSkipped() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "elsewhere/f"), bytes: 10)
        try FileManager.default.createSymbolicLink(at: home.appending(path: "link"),
                                                   withDestinationURL: home.appending(path: "elsewhere"))
        let items = await TargetScanner(home: home, running: notRunning).scan([target("a", ["~/link"])])
        #expect(items.isEmpty)
    }
}
