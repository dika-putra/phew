import Foundation

/// Measures path targets. Named TargetScanner to avoid clashing with Foundation.Scanner.
public struct TargetScanner: Sendable {
    let home: URL
    let running: RunningCheck

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, running: RunningCheck = .live) {
        self.home = home
        self.running = running
    }

    /// `alsoOwnedBy` lists targets that are not measured but whose folders stay out of `contents` targets.
    public func scan(_ targets: [PathTarget], alsoOwnedBy extra: [PathTarget] = []) async -> [Item] {
        let extraOwned = extra.filter { e in !targets.contains { $0.id == e.id } }
            .flatMap { t in t.paths.map { expandTilde($0, home: home).standardizedFileURL } }
        let owned = targets.map { t in t.paths.map { expandTilde($0, home: home).standardizedFileURL } }
        let ownCache = home.appending(path: "Library/Caches/com.dikaputra.phew").standardizedFileURL
        let results = await withTaskGroup(of: (Int, Item?).self) { group in
            for (index, target) in targets.enumerated() {
                let others = owned.enumerated().filter { $0.offset != index }.flatMap(\.element) + extraOwned + [ownCache]
                group.addTask { (index, scan(target, excluding: others)) }
            }
            var out: [(Int, Item?)] = []
            for await r in group { out.append(r) }
            return out
        }
        return results.sorted { $0.0 < $1.0 }.compactMap(\.1)
    }

    private func scan(_ target: PathTarget, excluding others: [URL]) -> Item? {
        let paths = target.paths.map { expandTilde($0, home: home).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            // A target folder that is a symlink (moved to another disk on purpose) is left alone.
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
        guard !paths.isEmpty else { return nil }

        var urls = paths
        if target.contents {
            urls = paths.flatMap { path in
                let children = (try? FileManager.default.contentsOfDirectory(
                    at: path, includingPropertiesForKeys: nil, options: [])) ?? []
                // A child that is, or contains, another target's folder belongs to that target.
                return children.map(\.standardizedFileURL).filter { child in
                    !others.contains { $0.pathComponents.starts(with: child.pathComponents) }
                }
            }
        }

        let size = DiskSize.allocated(urls)
        let bytes = size.bytes
        let unreadable = urls.filter { size.unreadable.contains($0) }.count
        let lastUsed = paths.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()

        let state: ItemState
        if let app = running.firstRunning(target.skipIfRunning) {
            state = .inUse(app: app)
        } else if !urls.isEmpty, unreadable == urls.count {
            state = .unreadable
        } else {
            state = .ready
        }
        return Item(id: target.id, target: target, urls: urls, bytes: bytes, lastUsed: lastUsed, state: state)
    }
}
