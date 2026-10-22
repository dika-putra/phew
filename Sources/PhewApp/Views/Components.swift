import PhewCore
import SwiftUI

func bytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

func relative(_ date: Date) -> String {
    Date.now.timeIntervalSince(date) < 60 ? "just now" : RelativeDateTimeFormatter().localizedString(for: date, relativeTo: .now)
}

extension EnvironmentValues {
    /// ImageRenderer draws nothing inside a ScrollView, so snapshot mode lays lists out flat.
    @Entry var isSnapshot = false
}

/// A ScrollView sized to its content (up to `maxHeight`), or a plain stack for snapshots.
/// In a MenuBarExtra window a ScrollView without a fixed height collapses to zero.
struct Scroll<Content: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    var maxHeight: CGFloat = 360
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        if isSnapshot {
            content
        } else {
            ScrollView {
                content.background(GeometryReader { geo in
                    Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                })
            }
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
            .frame(height: min(max(contentHeight, 1), maxHeight))
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension Tier {
    var label: String {
        switch self {
        case .regenerates: "Regenerates"
        case .redownload: "Redownload"
        case .dataLoss: "Data loss"
        }
    }

    var color: Color {
        switch self {
        case .regenerates: .green
        case .redownload: .blue
        case .dataLoss: .red
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}

struct TierBadge: View {
    let tier: Tier
    var body: some View { Badge(text: tier.label, color: tier.color) }
}

struct StateBadge: View {
    let state: ItemState

    var body: some View {
        switch state {
        case .ready: EmptyView()
        case .inUse(let app): Badge(text: "In use: \(app)", color: .orange)
        case .unreadable: Badge(text: "Needs Full Disk Access", color: .purple)
        case .locked(let reason): Badge(text: "Locked: \(reason)", color: .secondary)
        }
    }
}

struct DiskBar: View {
    let available: Int64
    let total: Int64

    var body: some View {
        GeometryReader { geo in
            let used = total > 0 ? CGFloat(total - available) / CGFloat(total) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.secondary).frame(width: geo.size.width * min(max(used, 0), 1))
            }
        }
        .frame(height: 6)
    }
}

struct Header: View {
    let title: String
    var back: (() -> Void)?
    var trailing: AnyView = AnyView(EmptyView())

    var body: some View {
        HStack(spacing: 8) {
            if let back {
                Button(action: back) { Image(systemName: "chevron.left").frame(width: 16, height: 16) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Back")
                    .keyboardShortcut(.cancelAction)
                    .help("Back (Esc)")
            } else {
                Image(systemName: "wind").foregroundStyle(.tint)
            }
            Text(title).font(.headline)
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

func count(_ n: Int, _ noun: String) -> String {
    "\(n) \(noun)\(n == 1 ? "" : "s")"
}
