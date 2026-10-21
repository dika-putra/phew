import Foundation
import PhewCore

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

func stateText(_ state: ItemState) -> String {
    switch state {
    case .ready: ""
    case .inUse(let app): "in use: \(app)"
    case .unreadable: "can't read"
    }
}

func status(_ message: String) {
    if isatty(2) == 1 { FileHandle.standardError.write(Data("\(message)\n".utf8)) }
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
}

func loadTargets() -> [PathTarget] {
    let loaded = ConfigStore().load()
    loaded.issues.forEach { warn($0.message) }
    return Catalog.all(custom: loaded.validTargets)
}

/// nil when no project folders are configured.
func scanProjects() async -> ProjectScan? {
    let config = ConfigStore().load().config
    guard !config.projectRoots.isEmpty else { return nil }
    status("Scanning project folders…")
    return await ProjectScanner(roots: config.projectRoots.map { URL(fileURLWithPath: $0) },
                                dormantDays: config.dormantDays).scan()
}

func printProjects(_ scan: ProjectScan) {
    let df = DateFormatter()
    df.dateStyle = .medium
    var byRoot: [(URL, [Item])] = []
    for item in scan.items {
        guard let root = item.project?.root else { continue }
        if let i = byRoot.firstIndex(where: { $0.0 == root }) { byRoot[i].1.append(item) } else { byRoot.append((root, [item])) }
    }
    print("\nProjects")
    for (root, items) in byRoot {
        let p = items[0].project!
        let when = p.lastModified.map { df.string(from: $0) } ?? "unknown"
        print("  \(p.name)  (\(p.stacks.joined(separator: ", ")))  changed \(when)\(p.dormant ? ", dormant" : "")  \(root.path)")
        for item in items {
            let rel = item.target.title.dropFirst(p.name.count + 2)
            print("    \(pad(String(rel), 28))  \(pad(formatBytes(item.bytes), 9))  \(item.target.tier.rawValue)")
        }
        let skipped = scan.skipped.filter { $0.url.path.hasPrefix(root.path + "/") }
        if !skipped.isEmpty { print("    \(skipped.count) skipped: tracked or not ignored by git") }
    }
    if byRoot.isEmpty { print("  nothing to clean") }
    scan.unreadable.forEach { warn("Can't read \($0.path)") }
}
