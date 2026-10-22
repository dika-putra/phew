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
    let m = AppModel(scan: { _ in fatalError() }, cache: tempCache(), available: { 10_000_000_000 },
                     notify: { spy.messages.append($0) }, alertSettings: { LowSpaceAlert(enabled: true, thresholdGB: 20) },
                     defaults: defaults)
    m.checkSpace()
    m.checkSpace()
    #expect(spy.messages.count == 1)
    #expect(spy.messages.first == "Only 10 GB left.")
}

@Test func adminScriptQuotesPathsForShellAndAppleScript() {
    let script = AdminDelete.script(cli: "/Applications/Phew.app/Contents/MacOS/phew",
                                    paths: ["/Library/Developer/CoreSimulator/Caches/dyld/25G83/it's \"x\""])
    #expect(script == #"do shell script "'/Applications/Phew.app/Contents/MacOS/phew' admin-delete-dyld '/Library/Developer/CoreSimulator/Caches/dyld/25G83/it'\\''s \"x\"'" with administrator privileges"#)
}

@Test func cliInstallerKeepsForeignSymlink() throws {
    let home = try tempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let bin = home.appending(path: ".local/bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: bin.appending(path: "phew"), withDestinationURL: URL(fileURLWithPath: "/src/phew/.build/debug/phew"))
    #expect(throws: CLIInstallerError.self) { try CLIInstaller.install(appBundle: home.appending(path: "Phew.app"), home: home) }
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: bin.appending(path: "phew").path) == "/src/phew/.build/debug/phew")
}

private func rgb(_ hex: UInt32) -> [Double] {
    [Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255]
}

private func luminance(_ c: [Double]) -> Double {
    let l = c.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
}

private func contrast(_ a: [Double], _ b: [Double]) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

/// WCAG ratio of badge text over its 15% tint on a white window, light mode.
@Test func badgeTextContrastLight() {
    #expect(Palette.lightValues.count == 6)
    for (name, hex) in Palette.lightValues {
        let fg = rgb(hex)
        let bg = fg.map { 0.85 + 0.15 * $0 }
        #expect(contrast(fg, bg) >= 4.5, "\(name)")
    }
}
