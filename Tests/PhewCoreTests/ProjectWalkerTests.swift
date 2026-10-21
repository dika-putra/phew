import Foundation
import Testing
@testable import PhewCore

func makeTree(_ root: URL, _ entries: [String]) throws {
    for e in entries {
        let url = root.appending(path: e)
        if e.hasSuffix("/") {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let content = e.hasSuffix("pubspec.yaml") ? "dependencies:\n  flutter:\n    sdk: flutter\n" : "x"
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private func rel(_ project: FoundProject) -> [String] {
    project.artifacts.map { String($0.url.standardizedFileURL.path.dropFirst(project.root.standardizedFileURL.path.count + 1)) }.sorted()
}

@Test func flutterAppGroupsPlatformArtifacts() throws {
    try withTempDir { dir in
        try makeTree(dir, ["app/pubspec.yaml", "app/build/x", "app/.dart_tool/x", "app/ios/Podfile.lock", "app/ios/Pods/x",
                           "app/android/build.gradle", "app/android/.gradle/x", "app/android/app/build/x"])
        let r = ProjectWalker.walk(roots: [dir])
        #expect(r.projects.count == 1)
        #expect(r.projects[0].root.lastPathComponent == "app")
        #expect(rel(r.projects[0]) == [".dart_tool", "android/.gradle", "android/app/build", "build", "ios/Pods"])
        #expect(Set(r.projects[0].stacks) == ["Flutter", "CocoaPods", "Gradle"])
    }
}

@Test func neverEntersPrunedFolders() throws {
    try withTempDir { dir in
        try makeTree(dir, ["proj/package.json", "proj/node_modules/dep/package.json", "proj/node_modules/dep/node_modules/x"])
        let r = ProjectWalker.walk(roots: [dir])
        #expect(r.projects.count == 1)
        #expect(rel(r.projects[0]) == ["node_modules"])
    }
}

@Test func monorepoWorkspacesGrouped() throws {
    try withTempDir { dir in
        try makeTree(dir, ["repo/package.json", "repo/apps/web/package.json", "repo/apps/web/node_modules/x", "repo/apps/web/.next/x"])
        let r = ProjectWalker.walk(roots: [dir])
        #expect(r.projects.count == 1)
        #expect(rel(r.projects[0]) == ["apps/web/.next", "apps/web/node_modules"])
    }
}

@Test func laravelPlusNodeListedOnce() throws {
    try withTempDir { dir in
        try makeTree(dir, ["site/artisan", "site/composer.json", "site/composer.lock", "site/package.json",
                           "site/vendor/x", "site/node_modules/x", "site/storage/logs/l.log", "site/bootstrap/cache/a.php",
                           "site/bootstrap/cache/.gitignore", "site/storage/app/keep"])
        let r = ProjectWalker.walk(roots: [dir])
        #expect(rel(r.projects[0]) == ["bootstrap/cache", "node_modules", "storage/logs", "vendor"])
        let boot = r.projects[0].artifacts.first { $0.url.lastPathComponent == "cache" }!
        #expect(boot.files.map(\.lastPathComponent) == ["a.php"])
        #expect(r.projects[0].artifacts.first { $0.url.lastPathComponent == "logs" }?.contents == true)
    }
}

@Test func pythonVenvAndPycache() throws {
    try withTempDir { dir in
        try makeTree(dir, ["py/pyproject.toml", "py/.venv/pyvenv.cfg", "py/.venv/lib/__pycache__/x", "py/pkg/__pycache__/x",
                           "py/env2/pyvenv.cfg"])
        let r = ProjectWalker.walk(roots: [dir])
        #expect(rel(r.projects[0]) == [".venv", "env2", "pkg/__pycache__"])
    }
}

@Test func unreadableRootReported() throws {
    try withTempDir { dir in
        try makeTree(dir, ["locked/p/package.json", "open/p/package.json", "open/p/node_modules/x"])
        let locked = dir.appending(path: "locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let r = ProjectWalker.walk(roots: [locked, dir.appending(path: "open")])
        #expect(r.projects.count == 1)
        #expect(r.unreadable.map(\.lastPathComponent) == ["locked"])
    }
}

@Test func lastModifiedIgnoresArtifacts() throws {
    try withTempDir { dir in
        try makeTree(dir, ["p/package.json", "p/src/a.js", "p/node_modules/x", "p/.angular/cache/y"])
        let old = Date(timeIntervalSince1970: 1_600_000_000)
        for f in ["p/package.json", "p/src/a.js"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: dir.appending(path: f).path)
        }
        let r = ProjectWalker.walk(roots: [dir])
        #expect(r.projects[0].lastModified == old)
    }
}
