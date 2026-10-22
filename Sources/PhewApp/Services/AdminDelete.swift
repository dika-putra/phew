import Foundation
import PhewCore

/// Deletes simulator dyld cache folders as root: the bundled `phew` CLI runs through
/// osascript's administrator prompt and checks the paths itself (PathGuard, dyld root only).
enum AdminDelete {
    static func script(cli: String, paths: [String]) -> String {
        let command = ([shellQuote(cli), "admin-delete-dyld"] + paths.map(shellQuote)).joined(separator: " ")
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    static func run(_ urls: [URL]) async -> AdminResult {
        let cli = Bundle.main.bundleURL.appending(path: "Contents/MacOS/phew").path
        guard FileManager.default.isExecutableFile(atPath: cli) else { return .failed("phew CLI not found in the app") }
        guard let result = try? await Shell.run("/usr/bin/osascript", ["-e", script(cli: cli, paths: urls.map(\.path))]) else {
            return .failed("Couldn't ask for the admin password")
        }
        if result.status == 0 { return .done }
        // osascript reports a cancelled password prompt as error -128.
        if result.stderr.contains("-128") { return .cancelled }
        return .failed(result.stderr.split(separator: "\n").first.map(String.init) ?? "Admin delete failed")
    }
}
