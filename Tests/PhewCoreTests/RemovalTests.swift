import Foundation
import Testing
@testable import PhewCore

final class CommandSpy: @unchecked Sendable {
    var calls: [[String]] = []
    var result: (([String]) -> ShellResult)?
}

private func stepItem(_ home: URL, steps: [Step]) -> Item {
    let t = PathTarget(id: "pnpm", group: "Node", title: "pnpm store", tier: .redownload, paths: ["~/store"])
    var i = Item(id: "pnpm", target: t, urls: [home.appending(path: "store")], bytes: 1_048_576, lastUsed: nil, state: .ready)
    i.removal = .steps(steps)
    return i
}

private func executor(_ home: URL, _ spy: CommandSpy) -> Executor {
    Executor(home: home, running: notRunning, devProcesses: DevProcessCheck { [] }, runCommand: { cmd in
        spy.calls.append(cmd)
        return spy.result?(cmd) ?? ShellResult(status: 0, stdout: "", stderr: "")
    })
}

@Test func commandRemovalRunsInOrder() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "store/f"), bytes: 1_048_576)
        let spy = CommandSpy()
        spy.result = { cmd in
            if cmd == ["pnpm", "store", "prune"] { try? FileManager.default.removeItem(at: home.appending(path: "store/f")) }
            return ShellResult(status: 0, stdout: "", stderr: "")
        }
        let item = stepItem(home, steps: [.run(["pnpm", "store", "prune"]), .run(["true"])])
        let receipt = await executor(home, spy).execute(Planner.plan([item], running: notRunning))
        #expect(spy.calls == [["pnpm", "store", "prune"], ["true"]])
        #expect(receipt.entries[0].measured >= 1_000_000)
        #expect(receipt.entries[0].failures.isEmpty)
    }
}

@Test func failingCommandRecordsStderr() async throws {
    try await withTempDirAsync { home in
        let spy = CommandSpy()
        spy.result = { _ in ShellResult(status: 1, stdout: "", stderr: "boom\nmore") }
        let item = stepItem(home, steps: [.run(["pnpm", "store", "prune"]), .run(["never"])])
        let receipt = await executor(home, spy).execute(Planner.plan([item], running: notRunning))
        #expect(receipt.entries[0].failures == ["pnpm store prune: boom"])
        #expect(spy.calls.count == 1)
    }
}

@Test func removeStepUsesTheGuard() async throws {
    try await withTempDirAsync { home in
        try writeFile(home.appending(path: "store/_npx/x"), bytes: 10)
        try writeFile(home.appending(path: "Documents/keep"), bytes: 10)
        let item = stepItem(home, steps: [.remove(home.appending(path: "store/_npx")), .remove(home.appending(path: "Documents"))])
        let receipt = await executor(home, CommandSpy()).execute(Planner.plan([item], running: notRunning))
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "store/_npx").path))
        #expect(FileManager.default.fileExists(atPath: home.appending(path: "Documents/keep").path))
        #expect(receipt.entries[0].failures.count == 1)
    }
}

@Test func lockedItemIsNeverPlanned() {
    let t = PathTarget(id: "nvm:24", group: "Versions", title: "Node 24", tier: .redownload, paths: ["~/n"])
    let i = Item(id: t.id, target: t, urls: [], bytes: 1, lastUsed: nil, state: .locked("Active Node version"))
    let plan = Planner.plan([i], running: notRunning)
    #expect(plan.items.isEmpty)
    #expect(plan.skipped.first?.reason == "Active Node version. Phew won't remove it.")
}

@Test func oldCacheWithoutRemovalDecodes() throws {
    let t = PathTarget(id: "a", group: "G", title: "A", tier: .regenerates, paths: ["~/a"])
    var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
        Item(id: "a", target: t, urls: [], bytes: 1, lastUsed: nil, state: .ready))) as! [String: Any]
    json.removeValue(forKey: "removal"); json.removeValue(forKey: "measure"); json.removeValue(forKey: "note")
    let item = try JSONDecoder().decode(Item.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(item.removal == .paths && item.measure == .paths && item.note == nil)
}
