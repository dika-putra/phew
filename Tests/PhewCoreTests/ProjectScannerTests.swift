import Foundation
import Testing
@testable import PhewCore

private func age(_ dir: URL, _ files: [String], days: Double) throws {
    let date = Date().addingTimeInterval(-days * 86_400)
    for f in files { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: dir.appending(path: f).path) }
}

@Test func itemsPerArtifactWithIds() async throws {
    try await withTempDirAsync { dir in
        try makeTree(dir, ["web/package.json", "web/node_modules/x"])
        let scan = await ProjectScanner(roots: [dir], dormantDays: 14).scan()
        let item = try #require(scan.items.first)
        #expect(item.id == "projects:\(dir.appending(path: "web/node_modules").standardizedFileURL.path)")
        #expect(item.target.group == "Projects")
        #expect(item.target.title == "web: node_modules")
        #expect(item.target.tier == .redownload)
        #expect(item.project?.name == "web")
        #expect(item.project?.stacks == ["Node"])
    }
}

@Test func dormantControlsPreselection() async throws {
    try await withTempDirAsync { dir in
        try makeTree(dir, ["old/package.json", "old/node_modules/x", "new/package.json", "new/node_modules/x"])
        try age(dir, ["old/package.json"], days: 30)
        try age(dir, ["new/package.json"], days: 2)
        let scan = await ProjectScanner(roots: [dir], dormantDays: 14).scan()
        let old = try #require(scan.items.first { $0.project?.name == "old" })
        let new = try #require(scan.items.first { $0.project?.name == "new" })
        #expect(old.project?.dormant == true && old.preselected)
        #expect(new.project?.dormant == false && !new.preselected)
    }
}

@Test(.enabled(if: Shell.which("git") != nil)) func gitRefusedArtifactIsSkipped() async throws {
    try await withTempDirAsync { dir in
        let repo = dir.appending(path: "app")
        try makeTree(repo, ["Cargo.toml", "target/x"])
        _ = try await Shell.run("git", ["-C", repo.path, "init", "-q"])
        let scan = await ProjectScanner(roots: [dir], dormantDays: 14).scan()
        #expect(scan.items.isEmpty)
        #expect(scan.skipped.first?.reason == "Not ignored by git")
    }
}

@Test(.enabled(if: Shell.which("git") != nil)) func laravelKeepsGitignore() async throws {
    try await withTempDirAsync { dir in
        let site = dir.appending(path: "site")
        try makeTree(site, ["artisan", "composer.json", "storage/logs/laravel.log"])
        try "*\n!.gitignore\n".write(to: site.appending(path: "storage/logs/.gitignore"), atomically: true, encoding: .utf8)
        _ = try await Shell.run("git", ["-C", site.path, "init", "-q"])
        _ = try await Shell.run("git", ["-C", site.path, "add", "storage/logs/.gitignore"])
        let scan = await ProjectScanner(roots: [dir], dormantDays: 14).scan()
        let logs = try #require(scan.items.first { $0.target.title == "site: storage/logs" })
        #expect(logs.urls.map(\.lastPathComponent) == ["laravel.log"])
    }
}

@Test func gitignoreChildNeverOfferedWithoutGit() async throws {
    try await withTempDirAsync { dir in
        try makeTree(dir, ["site/artisan", "site/composer.json", "site/storage/logs/.gitignore", "site/storage/logs/a.log"])
        let scan = await ProjectScanner(roots: [dir], dormantDays: 14).scan()
        let logs = try #require(scan.items.first)
        #expect(logs.urls.map(\.lastPathComponent) == ["a.log"])
    }
}

@Test func cleansThroughExecutor() async throws {
    try await withTempDirAsync { dir in
        try makeTree(dir, ["web/package.json", "web/node_modules/x"])
        let scan = await ProjectScanner(roots: [dir], dormantDays: 14).scan()
        let plan = Planner.plan(scan.items, running: notRunning)
        let receipt = await Executor(home: dir.appending(path: "home"), running: notRunning).execute(plan)
        #expect(receipt.entries.allSatisfy { $0.failures.isEmpty })
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "web/node_modules").path))
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "web/package.json").path))
    }
}
