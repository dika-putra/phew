import PhewCore
import SwiftUI
import UserNotifications

// Plain AppKit entry point, like dika-putra/heartbeat. A SwiftUI App needs at least one scene,
// and the placeholder Settings scene showed up as an empty "Phew Settings" window.
// The menu bar item is an NSStatusItem with an NSPopover (see AppDelegate), not a MenuBarExtra:
// a MenuBarExtra window kept its bottom edge when its height changed and slid under the menu bar.
@main
enum PhewMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()
    private let scheduler = BackgroundScan()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var previewWindow: NSWindow?
    private var spaceTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = ProcessInfo.processInfo.environment["PHEW_SNAPSHOT"] {
            Task { await Snapshots.write(model: model, to: URL(fileURLWithPath: dir)); NSApp.terminate(nil) }
            return
        }
        setUpStatusItem()
        applyAppearance()
        // The Appearance picker writes UserDefaults; apply it to the popover right away.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAppearance() }
        }
        scheduler.start { [model] in await model.refresh() }
        if model.isStale { Task { await model.refresh() } }
        UNUserNotificationCenter.current().delegate = self
        // First check only after the permission answer, or the first alert is dropped while the
        // alert state is already disarmed.
        Notifier.requestPermission { [model] in Task { @MainActor in model.checkSpace() } }
        spaceTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [model] _ in
            Task { @MainActor in model.checkSpace() }
        }
        // PHEW_PREVIEW=1 shows the popover content in a normal window (manual checks).
        if ProcessInfo.processInfo.environment["PHEW_PREVIEW"] != nil { showPreviewWindow() }
    }

    /// The popover inherits the status bar button's appearance (vibrant dark with a dark menu
    /// bar), not the app's, so the choice is set on the popover itself as well. nil follows the
    /// menu bar, which follows the system.
    private func applyAppearance() {
        let name: NSAppearance.Name? = switch Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") {
        case .light: .aqua
        case .dark: .darkAqua
        default: nil
        }
        let appearance = name.flatMap(NSAppearance.init(named:))
        if NSApp.appearance != appearance { NSApp.appearance = appearance }
        popover.appearance = appearance
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Phew")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        // The popover size is set by hand and the popover is re-anchored to the icon after each
        // change: with automatic sizing, a size change while shown made it jump to the screen edge.
        let content = ContentView(model: model)
            .frame(width: 360)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { geo in Color.clear.preference(key: PopoverSizeKey.self, value: geo.size) })
            .onPreferenceChange(PopoverSizeKey.self) { [weak self] size in
                MainActor.assumeIsolated { self?.resizePopover(to: size) }
            }
        popover.contentViewController = NSHostingController(rootView: content)
        popover.behavior = .transient
        popover.animates = false
    }

    private func resizePopover(to size: CGSize) {
        guard size.height > 0, popover.contentSize != size else { return }
        popover.contentSize = size
        if popover.isShown, let button = statusItem?.button {
            popover.positioningRect = button.bounds
        }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        let window = popover.contentViewController?.view.window
        window?.makeKey()
        // No control focused on open: macOS would put a focus ring on the first button (Refresh).
        window?.makeFirstResponder(nil)
    }

    private func showPreviewWindow() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(model: model).frame(width: 360)))
        window.title = "Phew preview"
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.model.screen = .home
            self.showPopover()
        }
        completionHandler()
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        screen
    }

    @ViewBuilder private var screen: some View {
        switch model.screen {
        case .home: HomeView(model: model)
        case .group(let name): GroupView(model: model, group: name)
        case .confirm(let plan):
            // Back to the group for a clean from one group, else (Quick clean) back to Home.
            let groups = Set((plan.items + plan.skipped.map(\.item)).map(\.target.group))
            ConfirmView(model: model, plan: plan, back: groups.count == 1 ? .group(groups.first!) : .home)
        case .cleaning(let title): CleaningView(title: title)
        case .receipt(let receipt): ReceiptView(model: model, receipt: receipt)
        case .settings: SettingsView(model: model)
        }
    }
}

/// Measures every 2 hours; macOS may delay it on battery or under load. Never deletes.
@MainActor
final class BackgroundScan {
    private var scheduler: NSBackgroundActivityScheduler?

    func start(_ work: @escaping @MainActor () async -> Void) {
        guard scheduler == nil else { return }
        let s = NSBackgroundActivityScheduler(identifier: "com.dikaputra.phew.scan")
        s.repeats = true
        s.interval = 2 * 3600
        s.tolerance = 600
        s.schedule { done in
            Task { @MainActor in
                await work()
                done(.finished)
            }
        }
        scheduler = s
    }
}

private struct PopoverSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
