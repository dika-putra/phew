import PhewCore
import SwiftUI

/// PHEW_SNAPSHOT=<folder>: renders each popover screen in light and dark to PNG files and quits.
/// Used to check the UI without clicking the menu bar.
@MainActor
enum Snapshots {
    static func write(model: AppModel, to folder: URL) async {
        if model.snapshot == nil { await model.refresh() }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var screens: [(String, Screen)] = [("home", .home), ("settings", .settings)]
        if let group = model.summary.groups.first?.id { screens.append(("group", .group(group))) }
        if model.summary.groups.contains(where: { $0.id == "Projects" }) { screens.append(("projects", .group("Projects"))) }
        for name in ["Versions", "Docker"] where model.summary.groups.contains(where: { $0.id == name })
            || (name == "Docker" && model.snapshot?.dockerOffBytes != nil) {
            screens.append((name.lowercased(), .group(name)))
        }
        if let group = model.summary.groups.first?.id {
            // Confirm and receipt are drawn from a plan only; nothing is deleted here.
            let plan = Planner.plan(Array(model.items(in: group).prefix(4)), running: .live)
            screens.append(("confirm", .confirm(plan)))
            let entries = plan.items.map { ReceiptEntry(itemID: $0.id, title: $0.target.title, claimed: $0.bytes,
                                                        measured: $0.bytes, failures: [], skippedReason: nil) }
                + plan.skipped.map { ReceiptEntry(itemID: $0.item.id, title: $0.item.target.title, claimed: $0.item.bytes,
                                                  measured: 0, failures: [], skippedReason: $0.reason) }
            screens.append(("receipt", .receipt(Receipt(entries: entries, freeBefore: model.available,
                                                        freeAfter: model.available + plan.expectedBytes))))
        }
        for (name, screen) in screens {
            model.screen = screen
            for scheme in [ColorScheme.light, .dark] {
                let view = ContentView(model: model)
                    .frame(width: 360)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme)
                    .environment(\.isSnapshot, true)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                try? png.write(to: folder.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
        model.screen = .home
    }
}
