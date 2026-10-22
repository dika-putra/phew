import ArgumentParser
import Foundation
import PhewCore

/// Run as root (through osascript from the app, or sudo from `phew clean`). Deletes only
/// folders inside the simulator dyld cache.
struct AdminDeleteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "admin-delete-dyld",
        abstract: "Internal: delete simulator dyld cache folders as root.",
        shouldDisplay: false
    )

    @Argument var paths: [String]

    func run() throws {
        guard getuid() == 0 else { throw ValidationError("Must run as root.") }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard adminDyldPathsAllowed(urls) else { throw ValidationError("Only folders inside \(dyldRoot.path) can be deleted.") }
        let guard_ = PathGuard(allowedRoots: [dyldRoot], home: URL(fileURLWithPath: "/var/root"))
        var failed = false
        for url in urls {
            do {
                try guard_.check(url)
                try FileManager.default.removeItem(at: url)
            } catch {
                FileHandle.standardError.write(Data("\(url.path): \(error)\n".utf8))
                failed = true
            }
        }
        if failed { throw ExitCode(1) }
    }
}

/// `phew clean` asks for the password in the terminal with sudo. `sudo -v` asks first, so a
/// cancelled or wrong password reads as "Admin password not given", not as a failed delete.
func sudoAdminDelete(_ urls: [URL], isTerminal: Bool = isatty(STDIN_FILENO) != 0,
                     sudo: @Sendable ([String]) async -> Int32 = runSudo) async -> AdminResult {
    guard isTerminal else { return .failed("Needs a terminal to ask for the admin password.") }
    guard await sudo(["-v"]) == 0 else { return .cancelled }
    let status = await sudo([Bundle.main.executablePath ?? CommandLine.arguments[0], "admin-delete-dyld"] + urls.map(\.path))
    return status == 0 ? .done : .failed("sudo admin-delete-dyld exited with \(status)")
}

/// Runs sudo in phew's own process group. Foundation's Process puts the child in a new group,
/// which is not the terminal's foreground group: sudo then stops (SIGTTIN) at the password
/// prompt and never returns.
@Sendable func runSudo(_ args: [String]) async -> Int32 {
    await Task.detached {
        let argv = (["/usr/bin/sudo"] + args).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        guard posix_spawn(&pid, "/usr/bin/sudo", nil, nil, argv, environ) == 0 else { return -1 }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        // WIFEXITED / WEXITSTATUS are macros Swift can't import.
        return status & 0x7f == 0 ? (status >> 8) & 0xff : -1
    }.value
}
