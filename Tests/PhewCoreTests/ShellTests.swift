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
