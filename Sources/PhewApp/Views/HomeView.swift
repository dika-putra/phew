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
            Header(title: "Phew", trailing: AnyView(HStack(spacing: 0) {
                IconButton(systemName: "arrow.clockwise", label: "Refresh") { Task { await model.refresh() } }
                    .disabled(model.isScanning)
                IconButton(systemName: "gearshape", label: "Settings (⌘,)") { model.screen = .settings }
            }))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(volume.name)
                    Spacer()
                    Text(bytes(model.available)).fontWeight(.semibold)
                    Text("available").foregroundStyle(.secondary)
                }
                DiskBar(available: model.available, total: volume.total)
                Text(model.isScanning ? scanningText : model.snapshot.map { "Scanned \(relative($0.date))" } ?? "Not scanned yet")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let last = model.lastClean {
                    Text("Last clean: \(bytes(last.freed)) freed, \(relative(last.date))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)

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
                                    Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .hoverHighlight()
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                        if !snapshot.items.contains(where: { $0.project != nil }) && !hasRoots {
                            Button { model.screen = .settings } label: {
                                Label("Add project folder", systemImage: "folder.badge.plus")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .hoverHighlight()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Group {
                    if model.isScanning { ProgressView(scanningText) } else { Text("No scan yet. Press Refresh.") }
                }
                .padding(24)
            }
        }
    }

    private var scanningText: String {
        model.scanStage.map { "Scanning: \($0)…" } ?? "Scanning…"
    }

    private var hasRoots: Bool { !ConfigStore().load().config.projectRoots.isEmpty }

    private func summary(_ s: Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Reclaimable").font(.subheadline).foregroundStyle(.secondary)
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
            // One line when it fits, else one badge per line (long sizes like "20,14 GB").
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { tierBadges(s) }
                VStack(alignment: .leading, spacing: 4) { tierBadges(s) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder private func tierBadges(_ s: Summary) -> some View {
        ForEach(Tier.allCases, id: \.self) { tier in
            Badge(text: "\(tier.label) \(bytes(s.byTier[tier] ?? 0))", color: tier.color)
        }
    }

    private func groupRow(_ group: GroupSummary) -> some View {
        HStack {
            Text(group.id)
            Spacer()
            Text(bytes(group.bytes)).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 12).padding(.vertical, 8)
        .hoverHighlight()
    }
}
