import PhewCore
import ServiceManagement
import SwiftUI

enum Appearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = Appearance.system.rawValue
    @State private var config = ConfigStore().load()
    @State private var loginError: String?
    @State private var cliMessage: String?
    @State private var saveError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let store = ConfigStore()

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "Settings", back: { model.screen = .home })
            Divider()
            Scroll(maxHeight: 460) {
                VStack(alignment: .leading, spacing: 0) {
                    row("Appearance") {
                        Picker("", selection: $appearance) {
                            ForEach(Appearance.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Project folders")
                            Spacer()
                            Button("Add…") { addRoot() }.controlSize(.small)
                        }
                        if config.config.projectRoots.isEmpty {
                            Text("None yet. Add the folder that holds your projects.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(config.config.projectRoots, id: \.self) { root in
                            HStack {
                                Text(root).font(.caption).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button { change { try store.removeProjectRoot(URL(fileURLWithPath: root)) } } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Remove \(root)")
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider()
                    row("Dormant after") {
                        Stepper("\(config.config.dormantDays) days", value: Binding(
                            get: { config.config.dormantDays },
                            set: { v in change { try store.update { $0.dormantDays = v } } }), in: 1...365)
                    }
                    row("Low space alert") {
                        Toggle("", isOn: Binding(
                            get: { config.config.lowSpaceAlert.enabled },
                            set: { v in change { try store.update { $0.lowSpaceAlert.enabled = v } } }))
                        .labelsHidden()
                        Stepper("Below \(config.config.lowSpaceAlert.thresholdGB) GB", value: Binding(
                            get: { config.config.lowSpaceAlert.thresholdGB },
                            set: { v in change { try store.update { $0.lowSpaceAlert.thresholdGB = v } } }), in: 5...200, step: 5)
                        .disabled(!config.config.lowSpaceAlert.enabled)
                    }
                    row("Launch at login") {
                        Toggle("", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })).labelsHidden()
                    }
                    if let loginError { note(loginError, .red) }
                    row("Full Disk Access") {
                        let granted = FullDiskAccess.isGranted
                        Badge(text: granted ? "Granted" : "Not granted", color: granted ? .green : .orange)
                        Button("Open settings") { FullDiskAccess.openSettings() }.controlSize(.small)
                    }
                    row("Command line tool") {
                        Button("Install phew") { installCLI() }.controlSize(.small)
                    }
                    if let cliMessage { note(cliMessage, .secondary) }
                    row("Custom targets") {
                        Text("\(config.validTargets.count)").foregroundStyle(.secondary)
                        Button("Open file") { NSWorkspace.shared.open(store.url) }.controlSize(.small)
                        Button("Reload") { config = store.load() }.controlSize(.small)
                    }
                    ForEach(config.issues, id: \.message) { note($0.message, .red) }
                    if let saveError { note(saveError, .red) }
                    about
                }
            }
        }
    }

    private var about: some View {
        VStack(spacing: 4) {
            Text("Phew \(AppInfo.version) (1)").fontWeight(.semibold)
            Text("by \(AppInfo.author)").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Link("View on GitHub", destination: AppInfo.repoURL)
                Link("Report an issue", destination: AppInfo.repoURL.appending(path: "issues"))
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                content()
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
        }
    }

    private func note(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption).foregroundStyle(color)
            .padding(.horizontal, 12).padding(.bottom, 6)
            .textSelection(.enabled)
    }

    private func change(_ action: () throws -> Void) {
        do {
            try action()
            saveError = nil
        } catch {
            saveError = "Couldn't save settings: \(error.localizedDescription)"
        }
        config = store.load()
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        change { try store.addProjectRoot(url) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func installCLI() {
        do {
            let link = try CLIInstaller.install(appBundle: Bundle.main.bundleURL)
            cliMessage = CLIInstaller.binOnPath()
                ? "Installed: \(link.path)"
                : "Installed: \(link.path). Add it to your PATH: export PATH=\"$HOME/.local/bin:$PATH\""
        } catch CLIInstallerError.fileExists(let path) {
            cliMessage = "\(path) already exists and is not a link from Phew. Remove it first."
        } catch {
            cliMessage = "Couldn't install: \(error.localizedDescription)"
        }
    }
}
