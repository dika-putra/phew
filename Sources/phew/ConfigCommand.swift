import ArgumentParser
import Foundation
import PhewCore

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Show the config, or add and remove project folders.",
        discussion: """
        Project folders are searched for build output and dependencies (node_modules, build, vendor, .venv and more).

        Examples:
          phew config
          phew config --add-root ~/Documents/Projects
          phew config --remove-root ~/Documents/Projects
        """
    )

    @Option(help: "Add a folder that holds your projects.")
    var addRoot: String?

    @Option(help: "Remove a project folder.")
    var removeRoot: String?

    func run() throws {
        let store = ConfigStore()
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let addRoot {
            let url = URL(fileURLWithPath: addRoot, relativeTo: cwd)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("No folder at \(url.path).")
            }
            do {
                try store.addProjectRoot(url)
            } catch ConfigError.protectedRoot(let path) {
                throw ValidationError("\(path) is too broad to scan as a project folder. Pick a folder inside it.")
            } catch {
                throw ValidationError("Couldn't update \(store.url.path): \(error.localizedDescription)")
            }
        }
        if let removeRoot {
            try store.removeProjectRoot(URL(fileURLWithPath: removeRoot, relativeTo: cwd))
        }
        let loaded = store.load()
        loaded.issues.forEach { warn($0.message) }
        print("Config: \(store.url.path)")
        print("Project folders:")
        if loaded.config.projectRoots.isEmpty { print("  none") }
        loaded.config.projectRoots.forEach { print("  \($0)") }
        print("Dormant after: \(loaded.config.dormantDays) days")
    }
}
