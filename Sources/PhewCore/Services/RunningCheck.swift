import AppKit

/// Finds a running app or process from a target's `skipIfRunning` list.
/// Entries are bundle ids, `proc:<pgrep -f pattern>` with an optional display name written as
/// `proc:<Name>=<pattern>`, or `env:<path>`: a process whose PATH or executable contains that
/// path (a terminal after `nvm use 16` has the version's bin folder on its PATH).
public struct RunningCheck: Sendable {
    private let runningBundleIDs: @Sendable () -> [String: String]
    private let processMatches: @Sendable (String) -> Bool
    private let environmentMatches: @Sendable (String) -> String?

    public init(
        runningBundleIDs: @Sendable @escaping () -> [String: String],
        processMatches: @Sendable @escaping (String) -> Bool,
        environmentMatches: @Sendable @escaping (String) -> String? = { _ in nil }
    ) {
        self.runningBundleIDs = runningBundleIDs
        self.processMatches = processMatches
        self.environmentMatches = environmentMatches
    }

    public static let live = RunningCheck(
        runningBundleIDs: {
            var apps: [String: String] = [:]
            for app in NSWorkspace.shared.runningApplications {
                if let id = app.bundleIdentifier { apps[id] = app.localizedName ?? id }
            }
            return apps
        },
        processMatches: { pattern in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            p.arguments = ["-qf", pattern]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return false }
            p.waitUntilExit()
            return p.terminationStatus == 0
        },
        environmentMatches: { path in
            // `ps -E` adds each process's environment after its command line (own user only).
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-Eww", "-o", "pid=,command=", "-U", String(getuid())]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let own = String(getpid())
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let fields = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard fields.count == 2, fields[0] != own, containsPathEntry(String(fields[1]), path) else { continue }
                return processDisplayName(String(fields[1].split(separator: " ").first ?? ""))
            }
            return nil
        }
    )

    public func firstRunning(_ identifiers: [String]) -> String? {
        guard !identifiers.isEmpty else { return nil }
        let apps = identifiers.contains { !$0.hasPrefix("proc:") } ? runningBundleIDs() : [:]
        for id in identifiers {
            if id.hasPrefix("env:") {
                if let name = environmentMatches(String(id.dropFirst(4))) { return name }
            } else if id.hasPrefix("proc:") {
                let spec = String(id.dropFirst(5))
                let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
                let (name, pattern) = parts.count == 2 ? (parts[0], parts[1]) : (spec, spec)
                if processMatches(pattern) { return name }
            } else if let name = apps[id] {
                return name
            }
        }
        return nil
    }
}

/// `path` appears as a whole PATH entry or as the start of an executable path inside it, so
/// ".../v16.20.2/bin" does not match ".../v16.20.20/bin".
func containsPathEntry(_ text: String, _ path: String) -> Bool {
    var search = text[...]
    while let range = search.range(of: path) {
        let next = search[range.upperBound...].first
        if next == nil || next == ":" || next == " " || next == "/" { return true }
        search = search[range.upperBound...]
    }
    return false
}

/// "/Applications/Claude.app/Contents/Helpers/disclaimer" -> "Claude", "-zsh" -> "zsh".
func processDisplayName(_ executable: String) -> String {
    if let app = executable.components(separatedBy: "/").last(where: { $0.hasSuffix(".app") }) {
        return String(app.dropLast(4))
    }
    let name = URL(fileURLWithPath: executable).lastPathComponent
    return name.hasPrefix("-") ? String(name.dropFirst()) : name
}
