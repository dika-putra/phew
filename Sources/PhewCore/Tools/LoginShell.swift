import Foundation

/// Tool commands run through the user's login shell: a GUI app does not get the shell's PATH,
/// so npm from nvm, go or rustup would not be found (and npm also needs node on PATH).
public func loginShell(_ command: String) -> [String] {
    [ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh", "-lc", command]
}

/// Single-quotes a value for a shell command line.
public func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Last non-empty stdout line: login shells may print a banner before the command's output.
func lastLine(_ result: ShellResult?) -> String? {
    guard let result, result.status == 0 else { return nil }
    return result.stdout.split(whereSeparator: \.isNewline).last.map { $0.trimmingCharacters(in: .whitespaces) }
        .flatMap { $0.isEmpty ? nil : $0 }
}

public let liveRun: @Sendable ([String]) async -> ShellResult? = { cmd in
    try? await Shell.run(cmd[0], Array(cmd.dropFirst()), timeout: .seconds(60))
}
