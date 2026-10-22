import Foundation
import Testing
@testable import PhewApp
@testable import PhewCore

private func tempHome() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appending(path: "phew-home-\(UUID().uuidString)").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func cliInstallerCreatesAndReplacesSymlink() throws {
    let home = try tempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let app1 = home.appending(path: "A/Phew.app"), app2 = home.appending(path: "B/Phew.app")
    let link = try CLIInstaller.install(appBundle: app1, home: home)
    #expect(link.path == home.appending(path: ".local/bin/phew").path)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == app1.appending(path: "Contents/MacOS/phew").path)
    _ = try CLIInstaller.install(appBundle: app2, home: home)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == app2.appending(path: "Contents/MacOS/phew").path)
}

@Test func cliInstallerRefusesRegularFile() throws {
    let home = try tempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let bin = home.appending(path: ".local/bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try "mine".write(to: bin.appending(path: "phew"), atomically: true, encoding: .utf8)
    #expect(throws: CLIInstallerError.self) { try CLIInstaller.install(appBundle: home.appending(path: "Phew.app"), home: home) }
    #expect(try String(contentsOf: bin.appending(path: "phew"), encoding: .utf8) == "mine")
}

final class Spy: @unchecked Sendable {
    var messages: [String] = []
}

@MainActor @Test func checkSpaceNotifiesOnce() throws {
    let spy = Spy()
    let defaults = UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!
    let m = AppModel(scan: { fatalError() }, cache: tempCache(), available: { 10_000_000_000 },
                     notify: { spy.messages.append($0) }, alertSettings: { LowSpaceAlert(enabled: true, thresholdGB: 20) },
                     defaults: defaults)
    m.checkSpace()
    m.checkSpace()
    #expect(spy.messages.count == 1)
    #expect(spy.messages.first?.hasPrefix("Only 10 GB left. Phew can free about") == true)
}

@Test func adminScriptQuotesPathsForShellAndAppleScript() {
    let script = AdminDelete.script(cli: "/Applications/Phew.app/Contents/MacOS/phew",
                                    paths: ["/Library/Developer/CoreSimulator/Caches/dyld/25G83/it's \"x\""])
    #expect(script == #"do shell script "'/Applications/Phew.app/Contents/MacOS/phew' admin-delete-dyld '/Library/Developer/CoreSimulator/Caches/dyld/25G83/it'\\''s \"x\"'" with administrator privileges"#)
}
