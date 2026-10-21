import Foundation

public enum Marker: Sendable {
    case file(String)
    case fileContaining(String, String)
    /// Any file in the folder whose name ends with this suffix, for example ".csproj".
    case fileExtension(String)
}

public enum ArtifactKind: Sendable {
    case folder(String)
    /// Delete the children, keep the folder (frameworks expect it to exist).
    case contents(String)
    case files(in: String, suffix: String)
    /// Every direct child folder that holds a `pyvenv.cfg`.
    case venvs
    /// Every folder with this name below the project, outside pruned folders.
    case recursive(String)
}

public struct Artifact: Sendable {
    public let kind: ArtifactKind
    public let tier: Tier
}

public struct ProjectRule: Sendable {
    public let stack: String
    /// Any of the groups matches; inside a group all markers must match.
    public let markers: [[Marker]]
    public let artifacts: [Artifact]
}

private func folders(_ tier: Tier, _ paths: String) -> [Artifact] {
    paths.split(separator: " ").map { Artifact(kind: .folder(String($0)), tier: tier) }
}

private func anyOf(_ names: String) -> [[Marker]] {
    names.split(separator: " ").map { [.file(String($0))] }
}

public enum ProjectRules {
    public static let pruned: Set<String> = Set("""
        node_modules build .dart_tool target dist .next .nuxt .output .svelte-kit .turbo .git vendor \
        .venv venv Pods .build .gradle .terraform _build deps obj bin \
        .opencode .claude .cursor .windsurf .aider .continue .codeium
        """.split(separator: " ").map(String.init))

    public static let all: [ProjectRule] = [
        ProjectRule(stack: "Flutter", markers: [[.fileContaining("pubspec.yaml", "sdk: flutter")]],
                    artifacts: folders(.regenerates, "build .dart_tool")),
        ProjectRule(stack: "Node", markers: anyOf("package.json"),
                    artifacts: folders(.redownload, "node_modules")
                        + folders(.regenerates, ".next .nuxt .output dist .svelte-kit .turbo .angular/cache .parcel-cache .expo .astro")),
        ProjectRule(stack: "Rust", markers: anyOf("Cargo.toml"), artifacts: folders(.regenerates, "target")),
        ProjectRule(stack: "PHP", markers: [[.file("composer.json"), .file("composer.lock")]],
                    artifacts: folders(.redownload, "vendor")),
        ProjectRule(stack: "Laravel", markers: [[.file("artisan"), .file("composer.json")]], artifacts: [
            Artifact(kind: .contents("storage/framework/cache/data"), tier: .regenerates),
            Artifact(kind: .contents("storage/framework/views"), tier: .regenerates),
            Artifact(kind: .contents("storage/logs"), tier: .regenerates),
            Artifact(kind: .files(in: "bootstrap/cache", suffix: ".php"), tier: .regenerates),
        ]),
        // Only caches. Never uploads, plugins or themes: those are the site's content.
        ProjectRule(stack: "WordPress", markers: anyOf("wp-config.php"), artifacts: [
            Artifact(kind: .contents("wp-content/cache"), tier: .regenerates),
            Artifact(kind: .contents("wp-content/upgrade"), tier: .regenerates),
        ]),
        ProjectRule(stack: "Python", markers: anyOf("pyproject.toml requirements.txt setup.py Pipfile"), artifacts: [
            Artifact(kind: .venvs, tier: .redownload),
            Artifact(kind: .recursive("__pycache__"), tier: .regenerates),
        ] + folders(.regenerates, ".pytest_cache .mypy_cache .ruff_cache .tox")),
        ProjectRule(stack: "CocoaPods", markers: anyOf("Podfile.lock"), artifacts: folders(.redownload, "Pods")),
        ProjectRule(stack: "SwiftPM", markers: anyOf("Package.swift"), artifacts: folders(.regenerates, ".build")),
        ProjectRule(stack: "Gradle", markers: anyOf("build.gradle build.gradle.kts settings.gradle settings.gradle.kts"),
                    artifacts: folders(.regenerates, "build .gradle .cxx app/build")),
        ProjectRule(stack: "Maven", markers: anyOf("pom.xml"), artifacts: folders(.regenerates, "target")),
        ProjectRule(stack: "Ruby", markers: anyOf("Gemfile.lock"), artifacts: folders(.redownload, "vendor/bundle")),
        ProjectRule(stack: ".NET", markers: [[.fileExtension(".csproj")], [.fileExtension(".sln")]],
                    artifacts: folders(.regenerates, "bin obj")),
        ProjectRule(stack: "Elixir", markers: anyOf("mix.exs"),
                    artifacts: folders(.regenerates, "_build") + folders(.redownload, "deps")),
        ProjectRule(stack: "Terraform", markers: [[.fileExtension(".tf")]], artifacts: folders(.redownload, ".terraform")),
    ]

    public static func matching(_ folder: URL) -> [ProjectRule] {
        let names = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        guard !names.isEmpty else { return [] }
        func matches(_ m: Marker) -> Bool {
            switch m {
            case .file(let name):
                return names.contains(name)
            case .fileExtension(let suffix):
                return names.contains { $0.hasSuffix(suffix) }
            case .fileContaining(let name, let text):
                guard names.contains(name),
                      let handle = FileHandle(forReadingAtPath: folder.appending(path: name).path) else { return false }
                defer { try? handle.close() }
                let head = (try? handle.read(upToCount: 65_536)) ?? Data()
                return String(decoding: head, as: UTF8.self).contains(text)
            }
        }
        return all.filter { rule in rule.markers.contains { group in group.allSatisfy(matches) } }
    }
}
