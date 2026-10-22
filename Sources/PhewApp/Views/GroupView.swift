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
        HStack(alignment: .top, spacing: 8) {
            Checkbox(state: model.selection.contains(item.id) ? .on : .off, label: "Select \(item.target.title)") {
                model.toggle(item.id)
            }
            .disabled(item.state == .unreadable || isLocked)
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? item.target.title).lineLimit(1).truncationMode(.middle)
                if let note = item.note {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                Text([bytes(item.bytes), item.lastUsed.map { "used \(relative($0))" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    TierBadge(tier: item.target.tier)
                    if item.target.flags.contains(.heavy) { Badge(text: "Heavy", color: .secondary) }
                    if item.target.flags.contains(.needsAdmin) { Badge(text: "Admin", color: .purple) }
                    StateBadge(state: item.state)
                }
            }
            Spacer()
            if item.state == .unreadable {
                Button("Enable") { FullDiskAccess.openSettings() }.controlSize(.small)
            }
            RevealButton(urls: Reveal.urls(for: item))
        }
        .padding(.leading, 12 + indent).padding(.trailing, 12).padding(.vertical, 7)
    }
}

struct GroupView: View {
    @Bindable var model: AppModel
    let group: String

    var body: some View {
        let items = model.items(in: group)
        VStack(spacing: 0) {
            Header(title: group, back: { model.screen = .home })
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
            HStack(alignment: .top, spacing: 8) {
                ProjectCheckbox(model: model, root: project.id)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(project.info.name).fontWeight(.semibold)
                        if project.info.dormant { Badge(text: "Dormant", color: .secondary) }
                    }
                    Text("\(bytes(project.bytes)) · \(project.info.stacks.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                RevealButton(urls: [project.id])
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
            ForEach(project.items) { item in
                ItemRow(model: model, item: item, title: String(item.target.title.dropFirst(project.info.name.count + 2)), indent: 22)
            }
            if !project.small.isEmpty {
                Button {
                    if expanded.contains(project.id) { expanded.remove(project.id) } else { expanded.insert(project.id) }
                } label: {
                    HStack {
                        Text("\(count(project.small.count, "small item")), \(bytes(project.small.reduce(0) { $0 + $1.bytes }))")
                        Image(systemName: expanded.contains(project.id) ? "chevron.up" : "chevron.down")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 4)
                if expanded.contains(project.id) {
                    ForEach(project.small) { item in
                        ItemRow(model: model, item: item, title: String(item.target.title.dropFirst(project.info.name.count + 2)), indent: 22)
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
        let ready = model.projectItems(root).filter { $0.state != .unreadable }
        let chosen = ready.filter { model.selection.contains($0.id) }.count
        Checkbox(state: chosen == 0 ? .off : chosen == ready.count ? .on : .mixed, label: "Select project") {
            model.toggleProject(root)
        }
        .disabled(ready.isEmpty)
    }
}

/// One checkbox look for items and projects (a native Toggle has no mixed state).
struct Checkbox: View {
    enum State { case off, on, mixed }
    let state: State
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .off ? "square" : state == .on ? "checkmark.square.fill" : "minus.square.fill")
                .font(.system(size: 15))
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Docker is off · \(bytes(diskBytes)) in Docker's disk.")
            Text("Start Docker to see and clean images and build cache.").font(.caption).foregroundStyle(.secondary)
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
