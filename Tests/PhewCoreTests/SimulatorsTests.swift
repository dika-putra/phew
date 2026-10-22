import Foundation
import Testing
@testable import PhewCore

private func fixtureData(_ name: String) throws -> Data {
    try Data(contentsOf: try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)))
}

private func simctlStub() throws -> @Sendable ([String]) async -> ShellResult? {
    let runtimes = String(decoding: try fixtureData("simctl-runtimes.json"), as: UTF8.self)
    let devices = String(decoding: try fixtureData("simctl-devices.json"), as: UTF8.self)
    return { cmd in
        if cmd.suffix(3) == ["runtime", "list", "-j"] { return ShellResult(status: 0, stdout: runtimes, stderr: "") }
        if cmd.suffix(3) == ["list", "devices", "-j"] { return ShellResult(status: 0, stdout: devices, stderr: "") }
        return nil
    }
}

@Test func parsesRuntimesAndBootedCount() throws {
    let runtimes = parseRuntimes(runtimesJSON: try fixtureData("simctl-runtimes.json"),
                                 devicesJSON: try fixtureData("simctl-devices.json"))
    #expect(runtimes.map(\.version) == ["18.5", "17.0"])
    #expect(runtimes[0].booted == 1 && runtimes[1].booted == 0)
    #expect(runtimes[0].sizeBytes == 8_270_000_000)
    #expect(runtimes[1].lastUsed != nil)
    #expect(runtimes[0].platform == "iOS")
}

@Test func bootedRuntimeInUse() async throws {
    let items = await Simulators.items(run: try simctlStub(), dyldRoot: URL(fileURLWithPath: "/nonexistent"))
    let r18 = try #require(items.first { $0.id == "ios.runtimes:8A2B0C1D-1111-4AAA-9BBB-000000000001" })
    #expect(r18.state == .inUse(app: "Simulator"))
    #expect(r18.target.title == "iOS 18.5 runtime")
    #expect(r18.measure == .runtime(uuid: "8A2B0C1D-1111-4AAA-9BBB-000000000001"))
    #expect(r18.target.flags.contains(.heavy))
}

@Test func unavailableSimulatorsItem() async throws {
    let items = await Simulators.items(run: try simctlStub(), dyldRoot: URL(fileURLWithPath: "/nonexistent"))
    let sims = try #require(items.first { $0.id == "ios.simulators" })
    #expect(sims.urls.map(\.lastPathComponent) == ["D4"])
    #expect(sims.removal == .steps([.retry(times: 3, delaySeconds: 3, ["/usr/bin/xcrun", "simctl", "delete", "unavailable"])]))
}

@Test func dyldFoldersAreAdminItems() async throws {
    try await withTempDirAsync { dir in
        try writeFile(dir.appending(path: "25G83/com.apple.CoreSimulator.SimRuntime.iOS-18-5.22F77/x"), bytes: 4096)
        let items = await Simulators.items(run: { _ in nil }, dyldRoot: dir)
        let dyld = try #require(items.first { $0.id.hasPrefix("ios.dyld:") })
        #expect(dyld.removal == .adminDyld)
        #expect(dyld.target.flags.contains(.needsAdmin))
        #expect(dyld.target.title == "Simulator dyld cache, iOS 18.5 (22F77)")
    }
}

@Test func adminCancelledIsSkipped() async throws {
    try await withTempDirAsync { dir in
        let t = PathTarget(id: "ios.dyld:x", group: "Xcode", title: "dyld", tier: .regenerates, flags: [.needsAdmin], paths: [dir.path])
        var item = Item(id: t.id, target: t, urls: [dir], bytes: 10, lastUsed: nil, state: .ready)
        item.removal = .adminDyld
        let receipt = await Executor(home: dir, running: notRunning, devProcesses: DevProcessCheck { [] },
                                     runAdmin: { _ in .cancelled }).execute(Planner.plan([item], running: notRunning))
        #expect(receipt.entries.first?.skippedReason == "Admin password not given")
        #expect(receipt.entries.first?.failures == [])
    }
}

@Test func adminDeleteRefusesOutsideRoot() {
    #expect(!adminDyldPathsAllowed([URL(fileURLWithPath: "/Library/Caches")]))
    #expect(!adminDyldPathsAllowed([URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld")]))
    #expect(!adminDyldPathsAllowed([URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld/../../x")]))
    #expect(adminDyldPathsAllowed([URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld/25G83/com.apple.x")]))
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["PHEW_REAL_TOOLS"] != nil))
func realSimulators() async {
    for i in await Simulators.items() { print("REAL \(i.id) \(i.target.title) \(i.bytes) \(i.state)") }
}

@Test func dyldSkipsEmptyAndOtherFolders() async throws {
    try await withTempDirAsync { dir in
        try FileManager.default.createDirectory(at: dir.appending(path: "25G83/inc"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appending(path: "25G83/com.apple.CoreSimulator.SimRuntime.iOS-17-0.21A328"),
                                                withIntermediateDirectories: true)
        let items = await Simulators.items(run: { _ in nil }, dyldRoot: dir)
        #expect(items.isEmpty)
    }
}
