import Foundation

/// Finds dev tools (next dev, vite, flutter run, gradle, rails…) whose working directory is
/// inside a project, so the project's build folders are not deleted under a running server.
public struct DevProcessCheck: Sendable {
    private let workingDirectories: @Sendable () -> [(name: String, cwd: String)]

    public init(workingDirectories: @Sendable @escaping () -> [(name: String, cwd: String)]) {
        self.workingDirectories = workingDirectories
    }

    public static let live = DevProcessCheck(commands: ["node", "bun", "deno", "dart", "flutter", "java", "ruby", "python", "php"])

    init(commands: [String]) {
        self.init {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            p.arguments = ["-a", "-d", "cwd", "-Fcn"] + commands.flatMap { ["-c", $0] }
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            // lsof -F: one field per line, "c<command>" then "n<path>".
            var result: [(name: String, cwd: String)] = []
            var command = ""
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if line.hasPrefix("c") { command = String(line.dropFirst()) }
                if line.hasPrefix("n") { result.append((command, String(line.dropFirst()))) }
            }
            return result
        }
    }

    /// Takes one snapshot of the processes; call `runningIn` on the result for many roots.
    public func snapshot() -> DevProcessCheck {
        let list = workingDirectories()
        return DevProcessCheck { list }
    }

    public func runningIn(_ root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        return workingDirectories().first { entry in
            URL(fileURLWithPath: entry.cwd).standardizedFileURL.resolvingSymlinksInPath()
                .pathComponents.starts(with: rootComponents)
        }?.name
    }
}
