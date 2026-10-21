import Foundation
import Testing
@testable import PhewCore

private func git(_ repo: URL, _ args: String...) async throws {
    let r = try await Shell.run("git", ["-C", repo.path, "-c", "user.name=t", "-c", "user.email=t@t"] + args)
    #expect(r.status == 0, "git \(args): \(r.stderr)")
}

private let hasGit = Shell.which("git") != nil

@Test(.enabled(if: hasGit)) func ignoredFolderAllowed() async throws {
    try await withTempDirAsync { repo in
        try await git(repo, "init", "-q")
        try makeTree(repo, [".gitignore", "node_modules/x"])
        try "node_modules\n".write(to: repo.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        let url = repo.appending(path: "node_modules")
        #expect(await GitSafety.check([url])[url] == .allowed)
    }
}

@Test(.enabled(if: hasGit)) func notIgnoredFolderRefused() async throws {
    try await withTempDirAsync { repo in
        try await git(repo, "init", "-q")
        try makeTree(repo, ["build/x"])
        let url = repo.appending(path: "build")
        #expect(await GitSafety.check([url])[url] == .notIgnored)
    }
}

@Test(.enabled(if: hasGit)) func trackedInsideIgnoredRefused() async throws {
    try await withTempDirAsync { repo in
        try await git(repo, "init", "-q")
        try makeTree(repo, ["vendor/a"])
        try "vendor/\n".write(to: repo.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try await git(repo, "add", "-f", "vendor/a", ".gitignore")
        try await git(repo, "commit", "-qm", "x")
        try makeTree(repo, ["vendor/b"])
        let url = repo.appending(path: "vendor")
        #expect(await GitSafety.check([url])[url] == .tracked)
    }
}

@Test func noRepoAllowed() async throws {
    try await withTempDirAsync { dir in
        try makeTree(dir, ["build/x"])
        let url = dir.appending(path: "build")
        #expect(await GitSafety.check([url])[url] == .allowed)
    }
}

@Test(.enabled(if: hasGit)) func laravelGitignoreChildTracked() async throws {
    try await withTempDirAsync { repo in
        try await git(repo, "init", "-q")
        try makeTree(repo, ["storage/logs/laravel.log"])
        try "*\n!.gitignore\n".write(to: repo.appending(path: "storage/logs/.gitignore"), atomically: true, encoding: .utf8)
        try await git(repo, "add", "storage/logs/.gitignore")
        try await git(repo, "commit", "-qm", "x")
        let keep = repo.appending(path: "storage/logs/.gitignore")
        let log = repo.appending(path: "storage/logs/laravel.log")
        let verdicts = await GitSafety.check([keep, log])
        #expect(verdicts[keep] == .tracked)
        #expect(verdicts[log] == .allowed)
    }
}

@Test(.enabled(if: hasGit)) func pathWithSpacesAndSubfolderRepo() async throws {
    try await withTempDirAsync { dir in
        let repo = dir.appending(path: "My Project")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try await git(repo, "init", "-q")
        try makeTree(repo, ["app one/node_modules/x"])
        try "node_modules\n".write(to: repo.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        let url = repo.appending(path: "app one/node_modules")
        #expect(await GitSafety.check([url])[url] == .allowed)
    }
}
