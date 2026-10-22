import ArgumentParser
import Foundation
import Testing
@testable import phew
@testable import PhewCore

@Test func everyCommandHasExamples() {
    let commands: [ParsableCommand.Type] = [Phew.self, ScanCommand.self, CleanCommand.self, ListCommand.self,
                                            VersionsCommand.self, ConfigCommand.self]
    for command in commands {
        let help = command.helpMessage()
        #expect(help.contains("Examples:"), "\(command)")
        #expect(help.components(separatedBy: "\n  phew ").count >= 3, "\(command) needs two examples")
    }
}

@Test func rootHelpListsCommandsInOrder() {
    let help = Phew.helpMessage()
    let positions = ["scan", "clean", "list", "versions", "config"].map { help.range(of: "\n  \($0) ")?.lowerBound }
    #expect(positions.allSatisfy { $0 != nil })
    #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted())
}

@Test func adminCommandIsHidden() {
    #expect(!Phew.helpMessage().contains("admin-delete-dyld"))
}

@Test func versionLine() {
    #expect(Phew.configuration.version == "phew 0.1.0 (https://github.com/dika-putra/phew)")
}

final class SudoSpy: @unchecked Sendable {
    var calls: [[String]] = []
}

@Test func cancelledSudoIsSkippedNotFailed() async {
    let spy = SudoSpy()
    let result = await sudoAdminDelete([URL(fileURLWithPath: "/tmp/x")], isTerminal: true) { args in
        spy.calls.append(args)
        return 1
    }
    #expect(result == .cancelled)
    #expect(spy.calls == [["-v"]])
}

@Test func failedDeleteAfterSudoIsAFailure() async {
    let result = await sudoAdminDelete([URL(fileURLWithPath: "/tmp/x")], isTerminal: true) { args in args == ["-v"] ? 0 : 1 }
    #expect(result == .failed("sudo admin-delete-dyld exited with 1"))
}

@Test func sudoRunsAdminDeleteWithThePaths() async {
    let spy = SudoSpy()
    let result = await sudoAdminDelete([URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")], isTerminal: true) { args in
        spy.calls.append(args)
        return 0
    }
    #expect(result == .done)
    #expect(spy.calls.count == 2)
    #expect(spy.calls.last?.suffix(3) == ["admin-delete-dyld", "/tmp/a", "/tmp/b"])
}

/// From cron or a script sudo can't ask; that is a failure (exit 1), not "password not given".
@Test func sudoWithoutTerminalFails() async {
    let spy = SudoSpy()
    let result = await sudoAdminDelete([URL(fileURLWithPath: "/tmp/x")], isTerminal: false) { args in
        spy.calls.append(args)
        return 0
    }
    #expect(result == .failed("Needs a terminal to ask for the admin password."))
    #expect(spy.calls.isEmpty)
}
