import Foundation
import Testing
@testable import PhewCore

private func versionItem(_ id: String) -> Item {
    var i = Item(id: id, target: PathTarget(id: id, group: "Versions", title: id, tier: .redownload, paths: ["/v"]),
                 urls: [], bytes: 1, lastUsed: nil, state: .ready)
    i.removal = .steps([.run(["fvm", "remove", "3.24.5"])])
    return i
}

@Test func lockIsRecheckedBeforeRemoving() async {
    let spy = CommandSpy()
    let executor = Executor(home: URL(fileURLWithPath: "/tmp"), running: notRunning, devProcesses: DevProcessCheck { [] },
                            runCommand: { spy.calls.append($0); return ShellResult(status: 0, stdout: "", stderr: "") },
                            currentLock: { $0.id == "fvm:3.24.5" ? "fvm global" : nil })
    let receipt = await executor.execute(Planner.plan([versionItem("fvm:3.24.5")], running: notRunning))
    #expect(spy.calls.isEmpty)
    #expect(receipt.entries.first?.skippedReason == "fvm global. Phew won't remove it.")
}

@Test func runtimeDeletesOnlyItsOwnSimulators() async throws {
    let runtimes = #"{"U1":{"build":"22F77","version":"18.5","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-5","sizeBytes":1}}"#
    let devices = #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-5":[{"udid":"D1","state":"Shutdown","isAvailable":true},{"udid":"D2","state":"Shutdown","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-16-4":[{"udid":"D9","state":"Shutdown","isAvailable":false}]}}"#
    let items = await Simulators.items(run: { cmd in
        if cmd.suffix(3) == ["runtime", "list", "-j"] { return ShellResult(status: 0, stdout: runtimes, stderr: "") }
        if cmd.suffix(3) == ["list", "devices", "-j"] { return ShellResult(status: 0, stdout: devices, stderr: "") }
        return nil
    }, dyldRoot: URL(fileURLWithPath: "/nonexistent"))
    let runtime = try #require(items.first { $0.id == "ios.runtimes:U1" })
    #expect(!"\(runtime.removal)".contains("unavailable"))
    #expect("\(runtime.removal)".contains("D1") && "\(runtime.removal)".contains("D2") && !"\(runtime.removal)".contains("D9"))
    #expect(runtime.note == "Also deletes 2 simulators of this runtime and their app data")
    #expect(runtime.target.skipIfRunning == ["proc:Simulator=CoreSimulator/Devices/D1/", "proc:Simulator=CoreSimulator/Devices/D2/"])
}

@Test func runningCheckSnapshotRunsPsOnce() {
    let count = CommandSpy()
    let check = RunningCheck(runningBundleIDs: { [:] }, processMatches: { _ in false },
                             environmentSnapshot: { count.calls.append(["ps"]); return ["zsh\tPATH=/a/bin"] })
    let snap = check.snapshot()
    _ = snap.firstRunning(["env:/a/bin"])
    _ = snap.firstRunning(["env:/b/bin"])
    #expect(count.calls.count == 1)
    #expect(snap.firstRunning(["env:/a/bin"]) == "zsh")
}
