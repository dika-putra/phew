import PhewCore
import SwiftUI
import UserNotifications

@main
struct PhewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar item is an NSStatusItem with an NSPopover (see AppDelegate), not a
    // MenuBarExtra: a MenuBarExtra window keeps its bottom edge when the content height
    // changes, so it slid under the menu bar or floated mid-screen. An NSPopover stays
    // anchored to the icon and resizes from the top. Same approach as dika-putra/heartbeat.
    var body: some Scene {
        Settings { EmptyView() }
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
        scheduler.start { [model] in await model.refresh() }
        if model.isStale { Task { await model.refresh() } }
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestPermission()
        model.checkSpace()
        spaceTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [model] _ in
            Task { @MainActor in model.checkSpace() }
        }
        // PHEW_PREVIEW=1 shows the popover content in a normal window (manual checks).
        if ProcessInfo.processInfo.environment["PHEW_PREVIEW"] != nil { showPreviewWindow() }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "wind", accessibilityDescription: "Phew")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        let host = NSHostingController(rootView: ContentView(model: model).frame(width: 360))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue

    var body: some View {
        screen.preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
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
