import Foundation

public struct Executor: Sendable {
    let home: URL
    let running: RunningCheck
    let devProcesses: DevProcessCheck

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, running: RunningCheck = .live,
                devProcesses: DevProcessCheck = .live) {
        self.home = home
        self.running = running
        self.devProcesses = devProcesses
    }

    public func execute(_ plan: CleanPlan, progress: @Sendable (String) -> Void = { _ in }) async -> Receipt {
        let freeBefore = DiskSize.available(for: home)
        var entries = plan.skipped.map {
            ReceiptEntry(itemID: $0.item.id, title: $0.item.target.title, claimed: $0.item.bytes,
                         measured: 0, failures: [], skippedReason: $0.reason)
        }
        let dev = plan.items.contains { $0.project != nil } ? devProcesses.snapshot() : nil
        for item in plan.items {
            progress(item.target.title)
            // An app or dev server may have started since the plan was made.
            if let reason = Planner.skipReason(item, running: running, dev: dev) {
                entries.append(ReceiptEntry(itemID: item.id, title: item.target.title, claimed: item.bytes,
                                            measured: 0, failures: [], skippedReason: reason))
                continue
            }
            entries.append(clean(item))
        }
        return Receipt(entries: entries, freeBefore: freeBefore, freeAfter: DiskSize.available(for: home))
    }

    private func clean(_ item: Item) -> ReceiptEntry {
        // One guard per target: an item may only delete inside its own target's paths.
        let guard_ = PathGuard(allowedRoots: item.target.paths.map { expandTilde($0, home: home) }, home: home)
        // Measured right before deleting, so a stale scan can never inflate the result.
        let before = item.urls.reduce(Int64(0)) { $0 + DiskSize.allocated($1).bytes }
        var failures: [String] = []
        // Items may come from a cached scan: a path that is gone now is not a failure.
        for url in item.urls where (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
            do {
                try guard_.check(url)
                try FileManager.default.removeItem(at: url)
            } catch {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))
                    .map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
                if isDir, !(error is PathGuardError) {
                    failures += removeEach(in: url, guard_)
                } else {
                    failures.append("\(url.path): \(describe(error))")
                }
            }
        }
        // Rule 1: report what is really gone, never the size of the selection.
        let remaining = item.urls.reduce(Int64(0)) { $0 + DiskSize.allocated($1).bytes }
        return ReceiptEntry(itemID: item.id, title: item.target.title, claimed: item.bytes,
                            measured: max(0, before - remaining), failures: failures, skippedReason: nil)
    }

    /// removeItem stops at the first error inside a folder. This removes what it can,
    /// deepest first, and names each entry that stays (for example a locked file).
    private func removeEach(in folder: URL, _ guard_: PathGuard) -> [String] {
        var entries: [URL] = []
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
        while let url = enumerator?.nextObject() as? URL { entries.append(url) }
        entries.append(folder)
        entries.sort { $0.pathComponents.count > $1.pathComponents.count }

        var failed: [String] = []
        for url in entries {
            let path = url.standardizedFileURL.path
            do {
                try guard_.check(url)
                try FileManager.default.removeItem(at: url)
            } catch {
                // A folder that still holds a failed entry is expected to stay; don't list it twice.
                if !failed.contains(where: { $0.hasPrefix(path + "/") }) {
                    failed.append("\(path): \(describe(error))")
                }
            }
        }
        return failed
    }

    private func describe(_ error: any Error) -> String {
        (error as? PathGuardError).map { "refused, \($0)" } ?? error.localizedDescription
    }
}
