import ArgumentParser
import Foundation
import PhewCore

struct ScanCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Measure what can be cleaned. Deletes nothing.",
        discussion: """
        Sizes are allocated sizes on disk. Items in use by a running app are marked and are not cleaned.

        Examples:
          phew scan
          phew scan --group Node
          phew scan --json
        """
    )

    @Option(help: "Show only one group, for example Xcode, Node or \"Extra folders\".")
    var group: String?

    @ArgumentParser.Flag(help: "Print JSON (schema version 1) instead of a table.")
    var json = false

    func run() async throws {
        let all = loadTargets()
        let targets = all.filter { group == nil || $0.group.caseInsensitiveCompare(group!) == .orderedSame }
        let wantsProjects = group == nil || group!.caseInsensitiveCompare("Projects") == .orderedSame
        if targets.isEmpty, !wantsProjects, let group {
            throw ValidationError("No group named \"\(group)\". Run `phew list` to see all groups.")
        }
        status("Scanning \(targets.count) targets…")
        let items = await TargetScanner().scan(targets, alsoOwnedBy: all)
        let projects = wantsProjects ? await scanProjects() : nil
        let available = DiskSize.available()
        if json {
            FileHandle.standardOutput.write(try scanJSON(items + (projects?.items ?? []), available: available))
            print()
            return
        }
        let idWidth = items.map(\.id.count).max() ?? 0
        var current = ""
        for item in items {
            if item.target.group != current {
                print(current.isEmpty ? item.target.group : "\n\(item.target.group)")
                current = item.target.group
            }
            print("  \(pad(item.id, idWidth))  \(pad(formatBytes(item.bytes), 9))  "
                + "\(pad(item.target.tier.rawValue, 11))  \(pad(stateText(item.state), 26))  \(item.target.title)")
        }
        if wantsProjects {
            if let projects { printProjects(projects) } else {
                print("\nNo project folders. Add one: phew config --add-root ~/Documents/Projects")
            }
        }
        let everything = items + (projects?.items ?? [])
        print()
        for tier in Tier.allCases {
            let total = everything.filter { $0.target.tier == tier }.reduce(Int64(0)) { $0 + $1.bytes }
            print("\(pad(tier.rawValue, 12)) \(formatBytes(total))")
        }
        print("\(pad("Total", 12)) \(formatBytes(everything.reduce(0) { $0 + $1.bytes }))")
        print("\(pad("Available", 12)) \(formatBytes(available))")
    }
}
