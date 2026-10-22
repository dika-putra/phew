import ArgumentParser
import Foundation
import PhewCore

struct CleanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Delete the targets you name, after showing the plan and asking.",
        discussion: """
        Items in use by a running app are skipped and listed with the reason. Deletes are permanent, \
        not moved to the Trash. The freed size shown is measured after deleting.

        Examples:
          phew clean xcode.deriveddata --dry-run
          phew clean gradle dart.analysis
          phew clean yarn --yes
          phew clean projects:~/Documents/Projects/old-app --dry-run
          phew clean projects --dry-run    (every dormant project item)
          phew clean nvm:v16.20.2 npm
        """
    )

    @Argument(help: "Target ids from `phew list`.")
    var ids: [String]

    @ArgumentParser.Flag(help: "Show the plan and stop. Deletes nothing.")
    var dryRun = false

    @ArgumentParser.Flag(help: "Clean without asking.")
    var yes = false

    func run() async throws {
        let all = loadTargets()
        let known = all.map(\.id)
        let projectIDs = ids.filter { $0 == "projects" || $0.hasPrefix("projects:") }
        let toolIDs = ids.filter { ToolScan.isToolItem($0) && !known.contains($0) }
        var tools: ToolScanResult?
        if !toolIDs.isEmpty { tools = await scanTools() }
        let toolKnown = tools?.items.map(\.id) ?? []
        for id in ids where !known.contains(id) && !projectIDs.contains(id) && !toolKnown.contains(id) {
            if ToolScan.isToolItem(id), id.hasPrefix("docker."), case .off = tools?.docker {
                throw ValidationError(dockerOffText)
            }
            let hints = suggestions(for: id, in: known)
            throw ValidationError(hints.isEmpty
                ? "Unknown id \"\(id)\". Run `phew list` to see ids."
                : "Unknown id \"\(id)\". Did you mean: \(hints.joined(separator: ", "))?")
        }
        if !dryRun, !yes, isatty(0) == 0 {
            throw ValidationError("Not a terminal. Pass --yes to clean without asking.")
        }

        let selected = all.filter { ids.contains($0.id) }
        status("Scanning…")
        var items = await TargetScanner().scan(selected, alsoOwnedBy: all)
        items += tools?.items.filter { ids.contains($0.id) } ?? []
        if !projectIDs.isEmpty {
            guard let projects = await scanProjects() else {
                throw ValidationError("No project folders. Add one: phew config --add-root ~/Documents/Projects")
            }
            // The shell does not expand ~ after "projects:", and stored roots are real paths (/tmp is /private/tmp).
            let normalized = projectIDs.map { id -> String in
                let path = String(id.dropFirst(9))
                guard id.hasPrefix("projects:"), path.hasPrefix("/") || path == "~" || path.hasPrefix("~/") else { return id }
                let url = expandTilde(path, home: FileManager.default.homeDirectoryForCurrentUser)
                return "projects:" + url.standardizedFileURL.resolvingSymlinksInPath().path
            }
            let match = matchProjectItems(normalized, in: projects.items)
            if let first = match.unknown.first {
                throw ValidationError("Nothing to clean for \(first). Use an absolute path, and run `phew scan --group Projects` to see project ids.")
            }
            items += match.matched
        }
        for id in ids where !projectIDs.contains(id) && !items.contains(where: { $0.id == id }) {
            print("Nothing to clean for \(id).")
        }
        let plan = Planner.plan(items, running: .live)
        printPlan(plan)
        if dryRun || plan.items.isEmpty { return }

        if !yes {
            Swift.print("Clean \(plan.items.count) items, \(formatBytes(plan.expectedBytes))? [y/N] ", terminator: "")
            guard let answer = readLine(), ["y", "yes"].contains(answer.lowercased()) else {
                print("Nothing deleted.")
                return
            }
        }
        let receipt = await Executor.live(runAdmin: { await sudoAdminDelete($0) }).execute(plan) { print("Cleaning \($0)…") }
        printReceipt(receipt)
        if receipt.entries.contains(where: { !$0.failures.isEmpty }) { throw ExitCode(1) }
    }

    private func printPlan(_ plan: CleanPlan) {
        for item in plan.items {
            print("  \(pad(formatBytes(item.bytes), 9))  \(pad(item.target.tier.rawValue, 11))  \(item.target.title)")
            if let note = item.note { print("             \(note)") }
            if item.target.tier == .dataLoss {
                print("             Deletes data you can't get back: \(item.target.title)")
            }
        }
        if !plan.skipped.isEmpty {
            print("\nSkipped")
            plan.skipped.forEach { print("  \($0.reason)") }
        }
        print("\nTotal: \(formatBytes(plan.expectedBytes)). Deleted for good, not moved to the Trash.")
        if plan.needsAdmin { print("You'll be asked for your Mac password (sudo).") }
    }

    private func printReceipt(_ receipt: Receipt) {
        print("\nPhew. \(formatBytes(receipt.measuredTotal)) freed.")
        for e in receipt.entries {
            if let reason = e.skippedReason {
                print("  \(pad(e.title, 28))  skipped: \(reason)")
            } else {
                print("  \(pad(e.title, 28))  \(formatBytes(e.measured))")
                e.failures.prefix(5).forEach { print("    failed: \($0)") }
                if e.failures.count > 5 { print("    and \(e.failures.count - 5) more") }
            }
        }
        print("Available: \(formatBytes(receipt.freeBefore)) -> \(formatBytes(receipt.freeAfter))")
        for m in receipt.mismatches {
            warn("\(m.title): expected \(formatBytes(m.claimed)), measured \(formatBytes(m.measured)).")
        }
    }
}
