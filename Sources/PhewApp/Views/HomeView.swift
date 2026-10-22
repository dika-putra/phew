import PhewCore
import SwiftUI

struct HomeView: View {
    @Bindable var model: AppModel

    private var volume: (name: String, total: Int64) {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey])
        return (v?.volumeLocalizedName ?? "Disk", Int64(v?.volumeTotalCapacity ?? 0))
    }

    var body: some View {
        VStack(spacing: 0) {
            Header(title: "Phew", trailing: AnyView(HStack(spacing: 10) {
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.isScanning)
                    .accessibilityLabel("Refresh")
                Button { model.screen = .settings } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }.buttonStyle(.borderless)))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(volume.name)
                    Spacer()
                    Text(bytes(model.available)).fontWeight(.semibold)
                    Text("available").foregroundStyle(.secondary)
                }
                DiskBar(available: model.available, total: volume.total)
                Text(model.isScanning ? "Scanning…" : model.snapshot.map { "Scanned \(relative($0.date))" } ?? "Not scanned yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.bottom, 10)

            Divider()
            if let snapshot = model.snapshot {
                summary(model.summary)
                Divider()
                Scroll(maxHeight: 330) {
                    VStack(spacing: 0) {
                        ForEach(model.summary.groups) { group in
                            Button { model.screen = .group(group.id) } label: { groupRow(group) }
                                .buttonStyle(.plain)
                            Divider()
                        }
                        if let off = snapshot.dockerOffBytes, !model.summary.groups.contains(where: { $0.id == "Docker" }) {
                            Button { model.screen = .group("Docker") } label: {
                                HStack {
                                    Text("Docker")
                                    Spacer()
                                    Text("off · \(bytes(off))").foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 12).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        if !snapshot.items.contains(where: { $0.project != nil }) && !hasRoots {
                            Button { model.screen = .settings } label: {
                                Label("Add project folder", systemImage: "folder.badge.plus")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Group {
                    if model.isScanning { ProgressView("Scanning your Mac…") } else { Text("No scan yet. Press Refresh.") }
                }
                .padding(24)
            }
        }
    }

    private var hasRoots: Bool { !ConfigStore().load().config.projectRoots.isEmpty }

    private func summary(_ s: Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reclaimable").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(bytes(s.reclaimable)).font(.title2).fontWeight(.semibold)
                Spacer()
                if s.reclaimable > 0 {
                    Button("Quick clean") { model.quickClean() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isCleaning)
                        .help("Cleans build output and caches that come back on their own or by download. Shows the list first.")
                }
            }
            HStack(spacing: 6) {
                ForEach(Tier.allCases, id: \.self) { tier in
                    Badge(text: "\(tier.label) \(bytes(s.byTier[tier] ?? 0))", color: tier.color)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func groupRow(_ group: GroupSummary) -> some View {
        HStack {
            Text(group.id)
            Spacer()
            Text(bytes(group.bytes)).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
