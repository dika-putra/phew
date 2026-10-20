import Foundation
import Testing
@testable import PhewCore

@Test func runsInHome() async throws {
    let r = try await Shell.run("/bin/pwd")
    #expect(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == FileManager.default.homeDirectoryForCurrentUser.path)
}

@Test func capturesNonZeroExit() async throws {
    let r = try await Shell.run("/bin/sh", ["-c", "echo err >&2; exit 3"])
    #expect(r.status == 3)
    #expect(r.stderr == "err\n")
}

@Test func largeOutputDoesNotDeadlock() async throws {
    let r = try await Shell.run("/bin/sh", ["-c", "yes a | tr -d '\\n' | head -c 1000000; yes b | tr -d '\\n' | head -c 200000 >&2"])
    #expect(r.stdout.count == 1_000_000)
    #expect(r.stderr.count == 200_000)
}

@Test func whichFindsLsAndNotNonsense() {
    #expect(Shell.which("ls")?.path == "/bin/ls")
    #expect(Shell.which("phew-no-such-tool") == nil)
}

@Test func unknownToolThrows() async {
    await #expect(throws: ShellError.self) { try await Shell.run("phew-no-such-tool") }
}

@Test func timesOut() async {
    await #expect(throws: ShellError.timedOut("/bin/sleep")) {
        try await Shell.run("/bin/sleep", ["5"], timeout: .milliseconds(200))
    }
}

@Test func whichIgnoresRelativePathEntries() throws {
    try withTempDir { dir in
        let tool = dir.appending(path: "phew-rel")
        try "#!/bin/sh\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        #expect(Shell.which("phew-rel", searchPath: [dir.path]) == tool)
        let relative = String(dir.path.dropFirst())  // "var/folders/..." relative to "/"
        let cwd = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath("/")
        defer { FileManager.default.changeCurrentDirectoryPath(cwd) }
        #expect(Shell.which("phew-rel", searchPath: ["", ".", relative]) == nil)
    }
}
