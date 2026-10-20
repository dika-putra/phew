import AppKit

/// Finds a running app or process from a target's `skipIfRunning` list.
/// Entries are bundle ids, or `proc:<pgrep -f pattern>` with an optional display name
/// written as `proc:<Name>=<pattern>`.
public struct RunningCheck: Sendable {
    private let runningBundleIDs: @Sendable () -> [String: String]
    private let processMatches: @Sendable (String) -> Bool

    public init(
        runningBundleIDs: @Sendable @escaping () -> [String: String],
        processMatches: @Sendable @escaping (String) -> Bool
    ) {
        self.runningBundleIDs = runningBundleIDs
        self.processMatches = processMatches
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
        }
    )

    public func firstRunning(_ identifiers: [String]) -> String? {
        guard !identifiers.isEmpty else { return nil }
        let apps = identifiers.contains { !$0.hasPrefix("proc:") } ? runningBundleIDs() : [:]
        for id in identifiers {
            if id.hasPrefix("proc:") {
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
