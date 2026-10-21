import ArgumentParser
import PhewCore

@main
struct Phew: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "phew",
        abstract: "Free disk space taken by developer files you can rebuild or download again.",
        discussion: """
        Examples:
          phew list
          phew list --group Xcode
          phew --version
        """,
        version: AppInfo.versionLine,
        subcommands: [ScanCommand.self, CleanCommand.self, ListCommand.self, ConfigCommand.self]
    )
}
