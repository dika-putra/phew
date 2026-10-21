import SwiftUI
import PhewCore

enum Reveal {
    /// What to select in Finder: the item's paths, or for a `contents` target (many children)
    /// the target's own folder.
    static func urls(for item: Item, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        if item.target.contents || item.urls.isEmpty {
            return item.target.paths.map { expandTilde($0, home: home) }
        }
        return item.urls
    }

    static func show(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

struct RevealButton: View {
    let urls: [URL]

    var body: some View {
        Button { Reveal.show(urls) } label: { Image(systemName: "folder") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")
    }
}
