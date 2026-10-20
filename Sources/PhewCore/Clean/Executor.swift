import Foundation

public struct Executor: Sendable {
    let home: URL
    let running: RunningCheck

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, running: RunningCheck = .live) {
        self.home = home
        self.running = running
    }

    public func execute(_ plan: CleanPlan, progress: @Sendable (String) -> Void = { _ in }) async -> Receipt {
        let freeBefore = DiskSize.available(for: home)
        var entries = plan.skipped.map {
            ReceiptEntry(itemID: $0.item.id, title: $0.item.target.title, claimed: $0.item.bytes,
                         measured: 0, failures: [], skippedReason: $0.reason)
        }
        for item in plan.items {
            progress(item.target.title)
            // An app may have started since the plan was made.
            if let reason = Planner.skipReason(item, running: running) {
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
        var failures: [String] = []
        for url in item.urls {
            do {
                try guard_.check(url)
                try FileManager.default.removeItem(at: url)
            } catch {
                let reason = (error as? PathGuardError).map { "refused, \($0)" } ?? error.localizedDescription
                failures.append("\(url.path): \(reason)")
            }
        }
        // Rule 1: report what is really gone, never the size of the selection.
        let remaining = item.urls.reduce(Int64(0)) { $0 + DiskSize.allocated($1).bytes }
        return ReceiptEntry(itemID: item.id, title: item.target.title, claimed: item.bytes,
                            measured: max(0, item.bytes - remaining), failures: failures, skippedReason: nil)
    }
}
