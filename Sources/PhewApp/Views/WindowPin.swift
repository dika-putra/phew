import AppKit
import SwiftUI

/// Keeps the MenuBarExtra window's top edge right under the menu bar. When the content grows,
/// the window keeps its bottom edge and its top slides under the menu bar; this moves it back.
struct PinWindowTop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PinView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class PinView: NSView {
        // ponytail: never removed in deinit; one PinView lives as long as the popover's root view.
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak window] _ in
                MainActor.assumeIsolated { if let window { Self.pin(window) } }
            }
            Self.pin(window)
        }

        private static func pin(_ window: NSWindow) {
            guard let screen = window.screen else { return }
            let top = screen.visibleFrame.maxY
            var frame = window.frame
            guard frame.maxY > top + 0.5 else { return }
            frame.origin.y = top - frame.height
            window.setFrame(frame, display: true)
        }
    }
}
