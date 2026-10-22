import Foundation

/// Finds dev tools (next dev, vite, flutter run, gradle, rails…) whose working directory is
/// inside a project, so the project's build folders are not deleted under a running server.
public struct DevProcessCheck: Sendable {
    private let workingDirectories: @Sendable () -> [(name: String, cwd: String)]

    public init(workingDirectories: @Sendable @escaping () -> [(name: String, cwd: String)]) {
        self.workingDirectories = workingDirectories
    }

    /// Only processes whose command line looks like a dev server count: tools such as MCP
    /// servers or editor language servers also run with their cwd in a project.
    public static let live = DevProcessCheck(
        commands: ["node", "npm", "pnpm", "yarn", "bun", "deno", "dart", "flutter", "java", "ruby", "python", "php"],
        filter: devServerName)

    init(commands: [String], filter: (@Sendable (String) -> String?)? = nil) {
        self.init {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            p.arguments = ["-a", "-d", "cwd", "-Fpcn"] + commands.flatMap { ["-c", $0] }
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return [] }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            // lsof -F: one field per line, "c<command>" then "n<path>".
            var found: [(pid: String, name: String, cwd: String)] = []
            var pid = "", command = ""
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if line.hasPrefix("p") { pid = String(line.dropFirst()) }
                if line.hasPrefix("c") { command = String(line.dropFirst()) }
                if line.hasPrefix("n") { found.append((pid, command, String(line.dropFirst()))) }
            }
            guard let filter, !found.isEmpty else { return found.map { ($0.name, $0.cwd) } }
            let lines = commandLines(found.map(\.pid))
            return found.compactMap { entry in
                lines[entry.pid].flatMap(filter).map { ($0, entry.cwd) }
            }
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

private func commandLines(_ pids: [String]) -> [String: String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/ps")
    p.arguments = ["-o", "pid=,command=", "-p", pids.joined(separator: ",")]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [:] }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    var result: [String: String] = [:]
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        if parts.count == 2 { result[String(parts[0])] = String(parts[1]) }
    }
    return result
}

private let devServerPatterns: [(pattern: String, name: String)] = [
    ("/next(\\.js)? (dev|start)", "next dev"), ("/vite(\\.js)?( |$)", "vite"), ("/nuxt (dev|start)", "nuxt dev"),
    ("/astro dev", "astro dev"), ("webpack(-dev-server| serve)", "webpack"), ("/expo start", "expo"),
    ("react-native start|metro", "metro"), ("flutter(_tools\\.snapshot)? (run|attach)", "flutter run"), ("GradleDaemon|gradlew? ", "Gradle"),
    ("artisan serve", "artisan serve"), ("php -S ", "php -S"), ("rails (s|server)( |$)", "rails server"),
    ("manage\\.py runserver", "runserver"), ("uvicorn|gunicorn|flask run", "python server"),
    ("(npm|pnpm|yarn|bun)( run)? (dev|start|serve)( |$)", "dev script"), ("deno (task|run) ", "deno"),
]

/// A short name when the command line looks like a dev server, else nil.
public func devServerName(_ commandLine: String) -> String? {
    devServerPatterns.first { commandLine.range(of: $0.pattern, options: .regularExpression) != nil }?.name
}
