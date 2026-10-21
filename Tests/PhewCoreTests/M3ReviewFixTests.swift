import Foundation
import Testing
@testable import PhewCore

@Test func artifactNameMustMatchCaseExactly() throws {
    try withTempDir { dir in
        try makeTree(dir, ["app/composer.json", "app/composer.lock", "app/Vendor/keep.php"])
        let r = ProjectWalker.walk(roots: [dir])
        #expect(r.projects.first?.artifacts.isEmpty ?? true)
    }
}

@Test func emptyOrRelativeProjectIdMatchesNothing() {
    let t = PathTarget(id: "projects:/a/web/node_modules", group: "Projects", title: "x", tier: .redownload,
                       paths: ["/a/web/node_modules"])
    let items = [Item(id: t.id, target: t, urls: [], bytes: 1, lastUsed: nil, state: .ready)]
    for id in ["projects:", "projects:.", "projects:a/web"] {
        #expect(matchProjectItems([id], in: items).matched.isEmpty, "\(id)")
    }
}

@Test func nestedRootsDoNotDuplicate() throws {
    try withTempDir { dir in
        try makeTree(dir, ["Projects/web/package.json", "Projects/web/node_modules/x"])
        let r = ProjectWalker.walk(roots: [dir, dir.appending(path: "Projects")])
        #expect(r.projects.flatMap(\.artifacts).count == 1)
    }
}

@Test func artifactHoldingGitRepoIsSkipped() async throws {
    try await withTempDirAsync { dir in
        try makeTree(dir, ["app/composer.json", "app/composer.lock", "app/vendor/acme/pkg/.git/HEAD", "app/vendor/acme/pkg/a.php"])
        let scan = await ProjectScanner(roots: [dir], dormantDays: 14).scan()
        #expect(scan.items.isEmpty)
        #expect(scan.skipped.first?.reason == "Holds a git repository (vendor/acme/pkg)")
    }
}
