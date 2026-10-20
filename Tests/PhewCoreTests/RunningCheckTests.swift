import Foundation
import Testing
@testable import PhewCore

private func stub(apps: [String: String] = [:], procs: Set<String> = []) -> RunningCheck {
    RunningCheck(runningBundleIDs: { apps }, processMatches: { procs.contains($0) })
}

@Test func findsRunningBundle() {
    #expect(stub(apps: ["com.apple.dt.Xcode": "Xcode"]).firstRunning(["com.apple.dt.Xcode"]) == "Xcode")
}

@Test func findsRunningProcess() {
    #expect(stub(procs: ["GradleDaemon"]).firstRunning(["proc:GradleDaemon"]) == "GradleDaemon")
}

@Test func processDisplayName() {
    #expect(stub(procs: ["GradleDaemon"]).firstRunning(["proc:Gradle=GradleDaemon"]) == "Gradle")
}

@Test func nothingRunning() {
    #expect(stub().firstRunning(["com.apple.dt.Xcode", "proc:x"]) == nil)
}

@Test func liveFindsSpawnedProcess() throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sleep")
    p.arguments = ["31.4159"]
    try p.run()
    defer { p.terminate() }
    #expect(RunningCheck.live.firstRunning(["proc:Sleeper=sleep 31\\.4159"]) == "Sleeper")
    #expect(RunningCheck.live.firstRunning(["proc:sleep 27\\.1828"]) == nil)
}
