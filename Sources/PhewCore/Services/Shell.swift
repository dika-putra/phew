import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum ShellError: Error, Equatable {
    case notFound(String)
}

public enum Shell {
    /// Runs `executable` (absolute path or a tool name looked up with `which`) with the
    /// working directory set to `$HOME`, so a deleted cwd never breaks child processes.
    public static func run(
        _ executable: String,
        _ args: [String] = [],
        environment: [String: String]? = nil
    ) async throws -> ShellResult {
        guard let url = executable.contains("/") ? URL(fileURLWithPath: executable) : which(executable),
              FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ShellError.notFound(executable)
        }
        let process = Process()
        process.executableURL = url
        process.arguments = args
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // Drain both pipes concurrently: a child that fills one pipe buffer blocks otherwise.
        async let outData = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
        let (o, e) = await (outData, errData)
        process.waitUntilExit()
        return ShellResult(
            status: process.terminationStatus,
            stdout: String(decoding: o, as: UTF8.self),
            stderr: String(decoding: e, as: UTF8.self)
        )
    }

    /// GUI apps start with a minimal PATH, so common tool folders are searched too.
    public static func which(_ tool: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.cargo/bin", "\(home)/.local/bin"]
        for dir in path + extra {
            let candidate = URL(fileURLWithPath: dir).appending(path: tool)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
