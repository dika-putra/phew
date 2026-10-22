import PhewCore
import SwiftUI

struct ItemRow: View {
    @Bindable var model: AppModel
    let item: Item
    var title: String? = nil
    var indent: CGFloat = 0

    private var isLocked: Bool {
        if case .locked = item.state { return true }
        return false
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Checkbox(state: model.selection.contains(item.id) ? .on : .off, label: "Select \(item.target.title)") {
                model.toggle(item.id)
            }
            .disabled(!model.isSelectable(item))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title ?? item.target.title).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if item.state == .unreadable {
                        Button("Enable") { FullDiskAccess.openSettings() }.controlSize(.small)
                    }
                    Text(bytes(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    RevealButton(urls: Reveal.urls(for: item))
                }
                .frame(height: 28)
                HStack(spacing: 4) {
                    TierBadge(tier: item.target.tier)
                    if item.target.flags.contains(.heavy) { Badge(text: "Heavy", color: Palette.gray) }
                    if item.target.flags.contains(.needsAdmin) { Badge(text: "Admin", color: Palette.purple) }
                    StateBadge(state: item.state)
                    if let detail = item.note ?? item.lastUsed.map({ "used \(relative($0))" }) {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.leading, 8 + indent).padding(.trailing, 8).padding(.vertical, 4)
        .hoverHighlight()
    }
}

struct GroupView: View {
    @Bindable var model: AppModel
    let group: String

    var body: some View {
        let items = model.items(in: group)
        VStack(spacing: 0) {
            Header(title: group, back: { model.screen = .home }, trailing: AnyView(
                Checkbox(state: model.selectionState(items), label: "Select all in \(group)") { model.toggleAll(items) }
                    .disabled(!items.contains(where: model.isSelectable))
                    .help("Select all")
            ))
            Divider()
            Scroll(maxHeight: 420) {
                VStack(spacing: 0) {
                    if group == "Docker", let off = model.snapshot?.dockerOffBytes {
                        DockerOffRow(model: model, diskBytes: off)
                        Divider()
                    }
                    if group == "Projects" {
                        ProjectsList(model: model, items: items)
                    } else {
                        ForEach(items) { item in
                            ItemRow(model: model, item: item)
                            Divider()
                        }
                    }
                }
            }
            SelectionFooter(model: model, items: items) { model.cleanSelected(in: group) }
        }
    }
}

struct ProjectsList: View {
    @Bindable var model: AppModel
    let items: [Item]
    @State private var expanded: Set<URL> = []

    var body: some View {
        ForEach(projectGroups(items)) { project in
            HStack(alignment: .top, spacing: 4) {
                ProjectCheckbox(model: model, root: project.id)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(project.info.name).fontWeight(.semibold)
                        if project.info.dormant { Badge(text: "Dormant", color: Palette.gray) }
                        Spacer()
                        Text(bytes(project.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        RevealButton(urls: [project.id])
                    }
                    .frame(height: 28)
                    Text(project.info.stacks.joined(separator: ", ")).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 4)
            .hoverHighlight()
            ForEach(project.items) { item in
                ItemRow(model: model, item: item, title: String(item.target.title.dropFirst(project.info.name.count + 2)), indent: 32)
            }
            if !project.small.isEmpty {
                Button {
                    if expanded.contains(project.id) { expanded.remove(project.id) } else { expanded.insert(project.id) }
                } label: {
                    HStack {
                        Text("\(count(project.small.count, "small item")), \(bytes(project.small.reduce(0) { $0 + $1.bytes }))")
                        Image(systemName: expanded.contains(project.id) ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 40).padding(.trailing, 12).padding(.vertical, 4)
                if expanded.contains(project.id) {
                    ForEach(project.small) { item in
                        ItemRow(model: model, item: item, title: String(item.target.title.dropFirst(project.info.name.count + 2)), indent: 32)
                    }
                }
            }
            Divider()
        }
    }
}

struct SelectionFooter: View {
    @Bindable var model: AppModel
    let items: [Item]
    let action: () -> Void

    var body: some View {
        let chosen = items.filter { model.selection.contains($0.id) }
        if !chosen.isEmpty {
            Divider()
            HStack {
                Text("\(count(chosen.count, "item")) · \(bytes(chosen.reduce(0) { $0 + $1.bytes }))")
                Spacer()
                Button("Clean selected", action: action).buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
    }
}

/// Checked when all cleanable items of the project are selected, a dash when some are.
struct ProjectCheckbox: View {
    @Bindable var model: AppModel
    let root: URL

    var body: some View {
        let items = model.projectItems(root)
        Checkbox(state: model.selectionState(items), label: "Select project") {
            model.toggleProject(root)
        }
        .disabled(!items.contains(where: model.isSelectable))
    }
}

/// One checkbox look for items and projects (a native Toggle has no mixed state).
struct Checkbox: View {
    let state: CheckState
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .off ? "square" : state == .on ? "checkmark.square.fill" : "minus.square.fill")
                .font(.system(size: 15))
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityValue(state == .on ? "checked" : state == .mixed ? "partly checked" : "unchecked")
    }
}

/// Phew never starts Docker by itself; this row explains why there is nothing to clean yet.
struct DockerOffRow: View {
    @Bindable var model: AppModel
    let diskBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Docker is off · \(bytes(diskBytes)) in Docker's disk.")
            Text("Start Docker to see and clean images and build cache.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button(model.isStartingDocker ? "Starting Docker…" : "Start Docker") { Task { await model.startDocker() } }
                    .controlSize(.small)
                    .disabled(model.isStartingDocker)
                if model.isStartingDocker { ProgressView().controlSize(.small) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
