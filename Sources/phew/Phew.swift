import ArgumentParser
import PhewCore

@main
struct Phew: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "phew",
        abstract: "Free disk space taken by developer files you can rebuild or download again.",
        version: AppInfo.versionLine,
        subcommands: []
    )
}
