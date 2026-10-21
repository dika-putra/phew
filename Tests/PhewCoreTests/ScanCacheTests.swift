import Foundation
import Testing
@testable import PhewCore

@Test func snapshotRoundTrip() throws {
    try withTempDir { dir in
        var p = item("p", bytes: 7, state: .inUse(app: "node"))
        p.project = ProjectInfo(root: URL(fileURLWithPath: "/a/web"), name: "web", stacks: ["Node"],
                                lastModified: Date(timeIntervalSince1970: 1_700_000_000), dormant: false)
        let snap = ScanSnapshot(date: Date(timeIntervalSince1970: 1_800_000_000), items: [item("a"), p],
                                skippedProjects: 2, unreadable: [URL(fileURLWithPath: "/x")])
        let cache = ScanCache(url: dir.appending(path: "c/scan.json"))
        try cache.save(snap)
        #expect(cache.load() == snap)
    }
}

@Test func corruptCacheIsNil() throws {
    try withTempDir { dir in
        let url = dir.appending(path: "scan.json")
        try "{".write(to: url, atomically: true, encoding: .utf8)
        #expect(ScanCache(url: url).load() == nil)
        #expect(ScanCache(url: dir.appending(path: "none.json")).load() == nil)
    }
}

@Test func missingUrlIsNotAFailure() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "a/f"), bytes: 10)
        let t = target("a", ["~/a"], contents: true)
        let it = Item(id: "a", target: t, urls: [home.appending(path: "a/f"), home.appending(path: "a/gone")],
                      bytes: 10, lastUsed: nil, state: .ready)
        let receipt = await Executor(home: home, running: notRunning).execute(Planner.plan([it], running: notRunning))
        #expect(receipt.entries[0].failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "a/f").path))
    }
}
