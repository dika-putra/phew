import Foundation

public struct ShellResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

public enum ShellError: Error, Equatable {
    case notFound(String)
    case timedOut(String)
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

public enum Shell {
    /// Runs `executable` (absolute path or a tool name looked up with `which`) with the
    /// working directory set to `$HOME`, so a deleted cwd never breaks child processes.
    public static func run(
        _ executable: String,
        _ args: [String] = [],
        environment: [String: String]? = nil,
        timeout: Duration = .seconds(600)
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
        // terminationHandler, not waitUntilExit: after an await the task may resume on another
        // thread, and waitUntilExit there was seen to wait forever for a child that had exited.
        let exit = AsyncStream<Int32> { continuation in
            process.terminationHandler = { p in
                continuation.yield(p.terminationStatus)
                continuation.finish()
            }
        }
        try process.run()

        // ponytail: kills only the direct child; a grandchild holding the pipe open still blocks.
        let box = ProcessBox(process)
        let timer = Task.detached { () -> Bool in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, box.process.isRunning else { return false }
            box.process.terminate()
            return true
        }

        // Drain both pipes concurrently: a child that fills one pipe buffer blocks otherwise.
        async let outData = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value
        let (o, e) = await (outData, errData)
        var status: Int32 = -1
        for await code in exit { status = code }
        timer.cancel()
        if await timer.value { throw ShellError.timedOut(executable) }
        return ShellResult(
            status: status,
            stdout: String(decoding: o, as: UTF8.self),
            stderr: String(decoding: e, as: UTF8.self)
        )
    }

    /// GUI apps start with a minimal PATH, so common tool folders are searched too.
    public static func which(_ tool: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":", omittingEmptySubsequences: false).map(String.init) ?? []
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.cargo/bin", "\(home)/.local/bin"]
        return which(tool, searchPath: path + extra)
    }

    /// Only absolute entries are searched: an empty or relative PATH entry means the cwd.
    static func which(_ tool: String, searchPath: [String]) -> URL? {
        for dir in searchPath where dir.hasPrefix("/") {
            let candidate = URL(fileURLWithPath: dir).appending(path: tool)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
