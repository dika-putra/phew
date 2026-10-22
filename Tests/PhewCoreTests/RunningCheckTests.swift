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

@Test func findsProcessByEnvironment() {
    let check = RunningCheck(runningBundleIDs: { [:] }, processMatches: { _ in false },
                             environmentMatches: { $0 == "/n/v16/bin" ? "zsh" : nil })
    #expect(check.firstRunning(["env:/n/v16/bin"]) == "zsh")
    #expect(check.firstRunning(["env:/n/v24/bin"]) == nil)
}

@Test func liveFindsOwnPathEntry() throws {
    // This test process inherits PATH, so its own PATH entries are found (Phew excludes its own pid, tests don't).
    let entry = try #require(ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").first.map(String.init))
    #expect(RunningCheck.live.firstRunning(["env:\(entry)"]) != nil)
}

@Test func processNameUsesAppBundle() {
    #expect(processDisplayName("/Applications/Claude.app/Contents/Helpers/disclaimer") == "Claude")
    #expect(processDisplayName("/bin/zsh") == "zsh")
    #expect(processDisplayName("-zsh") == "zsh")
}
