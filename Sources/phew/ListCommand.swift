import ArgumentParser
import Foundation
import PhewCore

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List every target id with its tier and flags.",
        discussion: """
        Use the ids with `phew clean`. Custom targets from ~/.config/phew/config.json are listed under Custom.

        Examples:
          phew list
          phew list --group Xcode
        """
    )

    @Option(help: "Show only one group, for example Xcode, Node or Custom.")
    var group: String?

    func run() throws {
        let loaded = ConfigStore().load()
        for issue in loaded.issues {
            FileHandle.standardError.write(Data("warning: \(issue.message)\n".utf8))
        }
        let targets = Catalog.all(custom: loaded.validTargets)
            .filter { group == nil || $0.group.caseInsensitiveCompare(group!) == .orderedSame }
        if targets.isEmpty, let group {
            throw ValidationError("No group named \"\(group)\". Run `phew list` to see all groups.")
        }
        let idWidth = targets.map(\.id.count).max() ?? 0
        var current = ""
        for t in targets {
            if t.group != current {
                print(current.isEmpty ? t.group : "\n\(t.group)")
                current = t.group
            }
            let flags = t.flags.map(\.rawValue).sorted().joined(separator: ",")
            let line = "  \(t.id.padding(toLength: idWidth, withPad: " ", startingAt: 0))  "
                + "\(t.tier.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0))  "
                + "\(flags.padding(toLength: 14, withPad: " ", startingAt: 0))  \(t.title)"
            print(line)
        }
    }
}
