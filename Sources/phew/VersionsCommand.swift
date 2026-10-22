import ArgumentParser
import Foundation
import PhewCore

struct VersionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "versions",
        abstract: "List installed Flutter (fvm), Node (nvm) and Rust (rustup) versions.",
        discussion: """
        Locked versions (the default or active one) are never removed. "Used by" lists projects in your \
        project folders that pin the version. Remove a version with `phew clean <id>`.

        Examples:
          phew versions
          phew versions nvm
          phew clean nvm:v16.20.2
        """
    )

    @Argument(help: "fvm, nvm or rustup. Leave out for all.")
    var tool: String?

    func run() async throws {
        if let tool, !["fvm", "nvm", "rustup"].contains(tool) {
            throw ValidationError("Unknown tool \"\(tool)\". Use fvm, nvm or rustup.")
        }
        let roots = ConfigStore().load().config.projectRoots.map { URL(fileURLWithPath: $0) }
        status("Checking versions…")
        let items = await Versions.items(home: FileManager.default.homeDirectoryForCurrentUser,
                                         pins: PinFinder.find(roots: roots))
            .filter { tool == nil || $0.id.hasPrefix(tool! + ":") }
        if items.isEmpty { print("No versions found."); return }
        let width = items.map(\.id.count).max() ?? 0
        for item in items {
            print("  \(pad(item.id, width))  \(pad(formatBytes(item.bytes), 9))  \(pad(stateText(item.state), 26))  \(item.note ?? "")")
        }
    }
}
