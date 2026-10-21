import PhewCore
import SwiftUI
import UserNotifications

@main
struct PhewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: delegate.model).frame(width: 360)
        } label: {
            Image(systemName: "wind")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()
    private let scheduler = BackgroundScan()
    private var previewWindow: NSWindow?
    private var spaceTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = ProcessInfo.processInfo.environment["PHEW_SNAPSHOT"] {
            Task { await Snapshots.write(model: model, to: URL(fileURLWithPath: dir)); NSApp.terminate(nil) }
            return
        }
        scheduler.start { [model] in await model.refresh() }
        if model.isStale { Task { await model.refresh() } }
        UNUserNotificationCenter.current().delegate = self
        Notifier.requestPermission()
        model.checkSpace()
        spaceTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [model] _ in
            Task { @MainActor in model.checkSpace() }
        }
        // PHEW_PREVIEW=1 shows the popover content in a normal window (screenshots, manual checks).
        if ProcessInfo.processInfo.environment["PHEW_PREVIEW"] != nil { showWindow() }
    }

    /// A menu bar popover can't be opened from code, so a click on the notification opens
    /// the same content in a small window.
    func showWindow() {
        if previewWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(model: model).frame(width: 360)))
            window.title = "Phew"
            window.isReleasedWhenClosed = false
            previewWindow = window
        }
        model.screen = .home
        previewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.showWindow() }
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
