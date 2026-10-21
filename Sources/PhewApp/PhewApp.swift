import PhewCore
import SwiftUI

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
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private let scheduler = BackgroundScan()
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = ProcessInfo.processInfo.environment["PHEW_SNAPSHOT"] {
            Task { await Snapshots.write(model: model, to: URL(fileURLWithPath: dir)); NSApp.terminate(nil) }
            return
        }
        scheduler.start { [model] in await model.refresh() }
        if model.isStale { Task { await model.refresh() } }
        // PHEW_PREVIEW=1 shows the popover content in a normal window (screenshots, manual checks).
        if ProcessInfo.processInfo.environment["PHEW_PREVIEW"] != nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ContentView(model: model).frame(width: 360)))
            window.title = "Phew preview"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            previewWindow = window
        }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.screen {
        case .home: HomeView(model: model)
        case .group(let name): GroupView(model: model, group: name)
        case .confirm(let plan):
            ConfirmView(model: model, plan: plan, back: plan.items.first.map { .group($0.target.group) } ?? .home)
        case .cleaning(let title): CleaningView(title: title)
        case .receipt(let receipt): ReceiptView(model: model, receipt: receipt)
        default:
            VStack {
                Header(title: "Coming soon", back: { model.screen = .home })
                Spacer(minLength: 120)
            }
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
