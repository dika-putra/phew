import Foundation
import Testing
@testable import PhewCore

let notRunning = RunningCheck(runningBundleIDs: { [:] }, processMatches: { _ in false })

func target(_ id: String, _ paths: [String], tier: Tier = .regenerates, flags: Set<Flag> = [],
            contents: Bool = false, skip: [String] = []) -> PathTarget {
    PathTarget(id: id, group: "Test", title: id.uppercased(), tier: tier, flags: flags,
               paths: paths, contents: contents, skipIfRunning: skip)
}

@Test func missingTargetsAreSkipped() async throws {
    try await withTempDirAsync { home in
        let items = await TargetScanner(home: home, running: notRunning).scan([target("a", ["~/nope"])])
        #expect(items.isEmpty)
    }
}

@Test func sizesNormalTarget() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "a/f"), bytes: 65_536)
        let items = await TargetScanner(home: home, running: notRunning).scan([target("a", ["~/a"])])
        #expect(items.count == 1)
        #expect(items[0].bytes >= 65_536)
        #expect(items[0].urls.map(\.path) == [home.appending(path: "a").path])
        #expect(items[0].lastUsed != nil)
    }
}

@Test func contentsTargetListsChildrenIncludingHidden() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "C/x"), bytes: 10)
        try writeFile(home.appending(path: "C/.y"), bytes: 10)
        let items = await TargetScanner(home: home, running: notRunning).scan([target("c", ["~/C"], contents: true)])
        #expect(items[0].urls.map(\.lastPathComponent).sorted() == [".y", "x"])
    }
}

@Test func contentsTargetExcludesOwnedFolders() async throws {
    try await withTempDirAsync { home in
        let caches = home.appending(path: "Library/Caches")
        try writeFile(caches.appending(path: "Homebrew/big"), bytes: 1_048_576)
        try writeFile(caches.appending(path: "com.dikaputra.phew/scan.json"), bytes: 1_048_576)
        try writeFile(caches.appending(path: "other/f"), bytes: 10)
        let items = await TargetScanner(home: home, running: notRunning).scan([
            target("macos.caches", ["~/Library/Caches"], contents: true),
            target("brew", ["~/Library/Caches/Homebrew"]),
        ])
        #expect(items[0].urls.map(\.lastPathComponent) == ["other"])
        #expect(items[0].bytes < 1_048_576)
        #expect(items[1].id == "brew")
    }
}

@Test func ancestorOfOwnedFolderIsExcluded() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "C/group/owned/f"), bytes: 10)
        try writeFile(home.appending(path: "C/free/f"), bytes: 10)
        let items = await TargetScanner(home: home, running: notRunning).scan([
            target("c", ["~/C"], contents: true),
            target("o", ["~/C/group/owned"]),
        ])
        #expect(items[0].urls.map(\.lastPathComponent) == ["free"])
    }
}

@Test func inUseState() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "a/f"), bytes: 10)
        let running = RunningCheck(runningBundleIDs: { ["com.x": "X"] }, processMatches: { _ in false })
        let items = await TargetScanner(home: home, running: running).scan([target("a", ["~/a"], skip: ["com.x"])])
        #expect(items[0].state == .inUse(app: "X"))
    }
}

@Test func preselectionRule() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "a/f"), bytes: 10)
        let scanner = TargetScanner(home: home, running: notRunning)
        func pre(_ tier: Tier, _ flags: Set<Flag> = []) async -> Bool {
            await scanner.scan([target("a", ["~/a"], tier: tier, flags: flags)])[0].preselected
        }
        #expect(await pre(.regenerates))
        #expect(await pre(.redownload))
        #expect(await !pre(.dataLoss))
        #expect(await !pre(.redownload, [.heavy]))
        #expect(await !pre(.regenerates, [.optIn]))
        #expect(await !pre(.regenerates, [.needsAdmin]))
    }
}

@Test func exclusionUsesTargetsOutsideTheScan() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "C/Homebrew/f"), bytes: 10)
        try writeFile(home.appending(path: "C/other/f"), bytes: 10)
        let items = await TargetScanner(home: home, running: notRunning).scan(
            [target("c", ["~/C"], contents: true)], alsoOwnedBy: [target("brew", ["~/C/Homebrew"])])
        #expect(items.map(\.id) == ["c"])
        #expect(items[0].urls.map(\.lastPathComponent) == ["other"])
    }
}

@Test func hardLinkAcrossChildrenCountedOnce() async throws {
    try await withTempDirAsync { home in
        let file = home.appending(path: "C/a/file")
        try writeFile(file, bytes: 1_048_576)
        try FileManager.default.createDirectory(at: home.appending(path: "C/b"), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: file, to: home.appending(path: "C/b/link"))
        let items = await TargetScanner(home: home, running: notRunning).scan([target("c", ["~/C"], contents: true)])
        #expect(items[0].bytes < 2 * 1_048_576)
    }
}
