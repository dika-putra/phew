import Foundation
import Testing
@testable import PhewCore

private func run(_ home: URL, _ targets: [PathTarget], planRunning: RunningCheck = notRunning,
                 execRunning: RunningCheck = notRunning) async -> Receipt {
    let items = await TargetScanner(home: home, running: notRunning).scan(targets)
    let plan = Planner.plan(items, running: planRunning)
    return await Executor(home: home, running: execRunning).execute(plan)
}

private func exists(_ url: URL) -> Bool {
    (try? url.checkResourceIsReachable()) == true || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
}

@Test func deletesAndMeasures() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "a/f"), bytes: 1_048_576)
        let receipt = await run(home, [target("a", ["~/a"])])
        #expect(receipt.entries.first?.measured ?? 0 >= 1_048_576)
        #expect(receipt.entries.first?.failures == [])
        #expect(!exists(home.appending(path: "a")))
    }
}

@Test func contentsKeepsFolderAndOwnedChild() async throws {
    try await withTempDirAsync { home in
        let c = home.appending(path: "C")
        try writeFile(c.appending(path: "x"), bytes: 10)
        try writeFile(c.appending(path: ".h"), bytes: 10)
        try writeFile(c.appending(path: "Homebrew/f"), bytes: 10)
        let all = [target("c", ["~/C"], contents: true), target("brew", ["~/C/Homebrew"])]
        let items = await TargetScanner(home: home, running: notRunning).scan(all)
        let plan = Planner.plan([items[0]], running: notRunning)
        _ = await Executor(home: home, running: notRunning).execute(plan)
        #expect(try FileManager.default.contentsOfDirectory(atPath: c.path) == ["Homebrew"])
    }
}

@Test func symlinkRemovedTargetKept() async throws {
    try await withTempDirAsync { home in
        let keep = home.appending(path: "keep/file")
        try writeFile(keep, bytes: 10)
        try FileManager.default.createDirectory(at: home.appending(path: "C"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appending(path: "C/link"), withDestinationURL: keep)
        _ = await run(home, [target("c", ["~/C"], contents: true)])
        #expect(!exists(home.appending(path: "C/link")))
        #expect(exists(keep))
    }
}

@Test func lockedFileIsAFailureNotACrash() async throws {
    try await withTempDirAsync { home in
        let locked = home.appending(path: "a/locked")
        try writeFile(locked, bytes: 10)
        try writeFile(home.appending(path: "b/f"), bytes: 10)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked.path) }
        let receipt = await run(home, [target("a", ["~/a"]), target("b", ["~/b"])])
        #expect(receipt.entries.first { $0.itemID == "a" }?.failures.isEmpty == false)
        #expect(!exists(home.appending(path: "b")))
    }
}

@Test func appStartedAfterPlanIsSkipped() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "a/f"), bytes: 10)
        let running = RunningCheck(runningBundleIDs: { ["com.x": "X"] }, processMatches: { _ in false })
        let receipt = await run(home, [target("a", ["~/a"], skip: ["com.x"])], execRunning: running)
        #expect(receipt.entries.first?.skippedReason == "X is running. Quit X to clean A.")
        #expect(exists(home.appending(path: "a")))
    }
}

@Test func guardRefusalIsAFailure() async throws {
    try await withTempDirAsync { home in
        let docs = home.appending(path: "Documents")
        try writeFile(docs.appending(path: "keep"), bytes: 10)
        let t = target("a", ["~/a"])
        let bad = Item(id: "a", target: t, urls: [docs], bytes: 10, lastUsed: nil, state: .ready)
        let receipt = await Executor(home: home, running: notRunning).execute(Planner.plan([bad], running: notRunning))
        #expect(receipt.entries.first?.failures.isEmpty == false)
        #expect(exists(docs.appending(path: "keep")))
    }
}

@Test func mismatchDetected() {
    let mib: Int64 = 1_048_576
    let receipt = Receipt(entries: [
        ReceiptEntry(itemID: "a", title: "A", claimed: 10 * mib, measured: mib, failures: [], skippedReason: nil),
        ReceiptEntry(itemID: "b", title: "B", claimed: 10 * mib, measured: 10 * mib, failures: [], skippedReason: nil),
        ReceiptEntry(itemID: "c", title: "C", claimed: 10 * mib, measured: 0, failures: [], skippedReason: "in use"),
    ], freeBefore: 0, freeAfter: 0)
    #expect(receipt.mismatches.map(\.itemID) == ["a"])
    #expect(receipt.measuredTotal == 11 * mib)
}
