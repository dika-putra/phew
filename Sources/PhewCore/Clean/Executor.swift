import Foundation

public struct Executor: Sendable {
    let home: URL
    let running: RunningCheck
    let devProcesses: DevProcessCheck
    let runCommand: @Sendable ([String]) async -> ShellResult?
    let dockerReclaimable: @Sendable (String) async -> Int64?
    let runtimePresent: @Sendable (String) async -> Bool?
    let runAdmin: @Sendable ([URL]) async -> AdminResult

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, running: RunningCheck = .live,
                devProcesses: DevProcessCheck = .live,
                runCommand: @escaping @Sendable ([String]) async -> ShellResult? = { cmd in
                    try? await Shell.run(cmd[0], Array(cmd.dropFirst()), timeout: .seconds(600))
                },
                dockerReclaimable: @escaping @Sendable (String) async -> Int64? = { _ in nil },
                runtimePresent: @escaping @Sendable (String) async -> Bool? = { _ in nil },
                runAdmin: @escaping @Sendable ([URL]) async -> AdminResult = { _ in .failed("Needs an administrator") }) {
        self.runAdmin = runAdmin
        self.home = home
        self.running = running
        self.devProcesses = devProcesses
        self.runCommand = runCommand
        self.dockerReclaimable = dockerReclaimable
        self.runtimePresent = runtimePresent
    }

    public func execute(_ plan: CleanPlan, progress: @Sendable (String) -> Void = { _ in }) async -> Receipt {
        let freeBefore = DiskSize.available(for: home)
        var entries = plan.skipped.map {
            ReceiptEntry(itemID: $0.item.id, title: $0.item.target.title, claimed: $0.item.bytes,
                         measured: 0, failures: [], skippedReason: $0.reason)
        }
        let dev = plan.items.contains { $0.project != nil } ? devProcesses.snapshot() : nil
        var admin: [Item] = []
        for item in plan.items {
            if item.removal == .adminDyld {
                admin.append(item)
                continue
            }
            progress(item.target.title)
            // An app or dev server may have started since the plan was made.
            if let reason = Planner.skipReason(item, running: running, dev: dev) {
                entries.append(ReceiptEntry(itemID: item.id, title: item.target.title, claimed: item.bytes,
                                            measured: 0, failures: [], skippedReason: reason))
                continue
            }
            entries.append(await clean(item))
        }
        if !admin.isEmpty {
            progress(admin[0].target.title)
            entries += await cleanAdmin(admin)
        }
        return Receipt(entries: entries, freeBefore: freeBefore, freeAfter: DiskSize.available(for: home))
    }

    private func clean(_ item: Item) async -> ReceiptEntry {
        // One guard per target: an item may only delete inside its own target's paths.
        let guard_ = PathGuard(allowedRoots: item.target.paths.map { expandTilde($0, home: home) }, home: home)
        // Measured right before deleting, so a stale scan can never inflate the result.
        let before = await size(of: item)
        var failures: [String] = []
        switch item.removal {
        case .paths:
            failures = removePaths(item.urls, guard_)
        case .steps(let steps):
            failures = await run(steps, guard_)
        case .adminDyld:
            failures = ["Needs an administrator"] // handled by cleanAdmin; not reached
        }
        let measured: Int64
        if case .runtime(let uuid) = item.measure {
            // Runtime folders are mounted disk images: count its size only once it is gone.
            measured = await runtimePresent(uuid) == false ? item.bytes : 0
        } else {
            measured = max(0, before - (await size(of: item)))
        }
        return ReceiptEntry(itemID: item.id, title: item.target.title, claimed: item.bytes,
                            measured: measured, failures: failures, skippedReason: nil)
    }

    /// All admin items go to one privileged call, so the password is asked once per clean.
    private func cleanAdmin(_ items: [Item]) async -> [ReceiptEntry] {
        let before = items.map { DiskSize.allocated($0.urls).bytes }
        let result = await runAdmin(items.flatMap(\.urls))
        return zip(items, before).map { item, before in
            switch result {
            case .cancelled:
                return ReceiptEntry(itemID: item.id, title: item.target.title, claimed: item.bytes, measured: 0,
                                    failures: [], skippedReason: "Admin password not given")
            case .failed(let message):
                return ReceiptEntry(itemID: item.id, title: item.target.title, claimed: item.bytes,
                                    measured: max(0, before - DiskSize.allocated(item.urls).bytes),
                                    failures: [message], skippedReason: nil)
            case .done:
                return ReceiptEntry(itemID: item.id, title: item.target.title, claimed: item.bytes,
                                    measured: max(0, before - DiskSize.allocated(item.urls).bytes),
                                    failures: [], skippedReason: nil)
            }
        }
    }

    private func size(of item: Item) async -> Int64 {
        switch item.measure {
        case .paths, .runtime: item.urls.reduce(Int64(0)) { $0 + DiskSize.allocated($1).bytes }
        case .docker: await dockerReclaimable(item.id) ?? 0
        }
    }

    private func removePaths(_ urls: [URL], _ guard_: PathGuard) -> [String] {
        var failures: [String] = []
        // Items may come from a cached scan: a path that is gone now is not a failure.
        for url in urls where (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil {
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
        return failures
    }

    /// Runs the steps in order and stops at the first one that fails.
    private func run(_ steps: [Step], _ guard_: PathGuard) async -> [String] {
        for step in steps {
            switch step {
            case .run(let cmd):
                if let failure = await failure(of: cmd) { return [failure] }
            case .remove(let url):
                let failures = removePaths([url], guard_)
                if !failures.isEmpty { return failures }
            case .retry(let times, let delay, let cmd):
                var last: String?
                for attempt in 1...max(times, 1) {
                    last = await failure(of: cmd)
                    if last == nil { break }
                    if attempt < times { try? await Task.sleep(for: .seconds(delay)) }
                }
                if let last { return [last] }
            }
        }
        return []
    }

    private func failure(of cmd: [String]) async -> String? {
        let name = cmd.joined(separator: " ")
        guard let result = await runCommand(cmd) else { return "\(name): couldn't run" }
        guard result.status != 0 else { return nil }
        let line = result.stderr.split(separator: "\n").first.map(String.init) ?? "exit code \(result.status)"
        return "\(name): \(line)"
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
