import Foundation
import Testing
@testable import PhewCore

private func folder(_ files: [String: String], _ body: (URL) throws -> Void) throws {
    try withTempDir { dir in
        for (name, content) in files {
            let url = dir.appending(path: name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try body(dir)
    }
}

private func stacks(_ dir: URL) -> [String] { ProjectRules.matching(dir).map(\.stack) }

@Test func flutterNeedsSdkFlutter() throws {
    try folder(["pubspec.yaml": "dependencies:\n  flutter:\n    sdk: flutter\n"]) { #expect(stacks($0) == ["Flutter"]) }
    try folder(["pubspec.yaml": "name: pure_dart\n"]) { #expect(stacks($0) == []) }
}

@Test func laravelAndNodeBothMatch() throws {
    try folder(["artisan": "", "composer.json": "{}", "composer.lock": "{}", "package.json": "{}"]) { dir in
        let s = stacks(dir)
        for stack in ["Laravel", "PHP", "Node"] { #expect(s.contains(stack), "\(stack)") }
    }
}

@Test func laravelNeedsBothMarkers() throws {
    try folder(["artisan": ""]) { #expect(!stacks($0).contains("Laravel")) }
}

@Test func wordpressNeverTouchesContent() {
    let wp = ProjectRules.all.first { $0.stack == "WordPress" }!
    for a in wp.artifacts {
        let path: String = switch a.kind {
        case .folder(let p), .contents(let p): p
        case .files(let p, _): p
        case .venvs: ""
        case .recursive(let p): p
        }
        for bad in ["uploads", "plugins", "themes"] { #expect(!path.contains(bad)) }
    }
}

@Test func dotnetByExtension() throws {
    try folder(["App.csproj": "<Project/>"]) { #expect(stacks($0) == [".NET"]) }
}

@Test func noMarkerNoMatch() throws {
    try folder(["build/x": "", "dist/y": ""]) { #expect(stacks($0) == []) }
}

@Test func prunedListMatchesSpec() {
    let expected = "node_modules build .dart_tool target dist .next .nuxt .output .svelte-kit .turbo .git vendor .venv venv Pods .build .gradle .terraform _build deps obj bin .opencode .claude .cursor .windsurf .aider .continue .codeium"
    for name in expected.split(separator: " ") { #expect(ProjectRules.pruned.contains(String(name)), "\(name)") }
}
