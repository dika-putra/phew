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

/// Badge and status colors. Light mode uses darker shades than the system colors, which fall
/// below a 4.5:1 contrast ratio on their own 15% tint; dark mode keeps the system colors.
enum Palette {
    static let lightValues: [String: UInt32] = [
        "green": 0x116329, "blue": 0x0550AE, "orange": 0x953800,
        "red": 0xA40E26, "purple": 0x6639BA, "gray": 0x57606A,
    ]
    static let green = color("green", dark: .systemGreen)
    static let blue = color("blue", dark: .systemBlue)
    static let orange = color("orange", dark: .systemOrange)
    static let red = color("red", dark: .systemRed)
    static let purple = color("purple", dark: .systemPurple)
    static let gray = color("gray", dark: .secondaryLabelColor)

    private static func color(_ name: String, dark: NSColor) -> Color {
        let hex = lightValues[name]!
        let light = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
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
        case .regenerates: Palette.green
        case .redownload: Palette.blue
        case .dataLoss: Palette.red
        }
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
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
        case .inUse(let app): Badge(text: "In use: \(app)", color: Palette.orange)
        case .unreadable: Badge(text: "Needs Full Disk Access", color: Palette.purple)
        case .locked(let reason): Badge(text: "Locked: \(reason)", color: Palette.gray)
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
                IconButton(systemName: "chevron.left", label: "Back (Esc)", action: back)
                    .keyboardShortcut(.cancelAction)
            } else {
                Image(systemName: "wind").foregroundStyle(.tint)
            }
            Text(title).font(.headline)
            Spacer()
            trailing
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Icon-only button with the HIG 28x28 pt hit area.
struct IconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct HoverHighlight: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(hovered ? Color.primary.opacity(0.06) : .clear)
            .onHover { hovered = $0 }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

func count(_ n: Int, _ noun: String) -> String {
    "\(n) \(noun)\(n == 1 ? "" : "s")"
}
