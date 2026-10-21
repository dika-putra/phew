import AppKit

enum FullDiskAccess {
    /// ~/Library/Safari is readable only with Full Disk Access.
    static var isGranted: Bool {
        let safari = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari").path
        return (try? FileManager.default.contentsOfDirectory(atPath: safari)) != nil
    }

    static func openSettings() {
        // Verify on new macOS versions: the System Settings URL scheme has changed before.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
