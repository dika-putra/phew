import Foundation

enum CLIInstallerError: Error, Equatable {
    case fileExists(String)
}

enum CLIInstaller {
    /// Links ~/.local/bin/phew to the CLI inside the app. Replaces an older link, never a real file.
    static func install(appBundle: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let fm = FileManager.default
        let bin = home.appending(path: ".local/bin")
        let link = bin.appending(path: "phew")
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil {
            try fm.removeItem(at: link)
        } else if fm.fileExists(atPath: link.path) {
            throw CLIInstallerError.fileExists(link.path)
        }
        try fm.createSymbolicLink(at: link, withDestinationURL: appBundle.appending(path: "Contents/MacOS/phew"))
        return link
    }

    /// True when ~/.local/bin is on the PATH of the user's login shell.
    static func binOnPath(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lc", "echo $PATH"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: ":")
            .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == home.appending(path: ".local/bin").path }
    }
}
