import ArgumentParser
import PhewCore

@main
struct Phew: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "phew",
        abstract: "Free disk space taken by developer files you can rebuild or download again.",
        discussion: """
        Scan first, then clean the ids you pick. Nothing is deleted without showing the plan.

        Examples:
          phew scan
          phew clean xcode.deriveddata --dry-run
          phew config --add-root ~/Documents/Projects
          phew help clean
        """,
        version: AppInfo.versionLine,
        subcommands: [ScanCommand.self, CleanCommand.self, ListCommand.self, VersionsCommand.self, ConfigCommand.self, AdminDeleteCommand.self]
    )
}
