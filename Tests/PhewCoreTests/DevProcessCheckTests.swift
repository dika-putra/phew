import Foundation
import Testing
@testable import PhewCore

private func stub(_ list: [(String, String)]) -> DevProcessCheck {
    DevProcessCheck(workingDirectories: { list.map { (name: $0.0, cwd: $0.1) } })
}

@Test func findsProcessInsideRoot() {
    let check = stub([("node", "/a/web/src")])
    #expect(check.runningIn(URL(fileURLWithPath: "/a/web")) == "node")
    #expect(check.runningIn(URL(fileURLWithPath: "/a/website")) == nil)
}

@Test func projectArtifactsMarkedInUse() async throws {
    try await withTempDirAsync { dir in
        try makeTree(dir, ["web/package.json", "web/node_modules/x"])
        let web = dir.appending(path: "web").path
        let scan = await ProjectScanner(roots: [dir], dormantDays: 0, devProcesses: stub([("node", web)])).scan()
        let item = try #require(scan.items.first)
        #expect(item.state == .inUse(app: "node"))
        #expect(!item.preselected)
    }
}

@Test func plannerSkipsInUseProjectItem() {
    let t = PathTarget(id: "projects:/a/web/node_modules", group: "Projects", title: "web: node_modules",
                       tier: .redownload, paths: ["/a/web/node_modules"])
    let it = Item(id: t.id, target: t, urls: [], bytes: 1, lastUsed: nil, state: .inUse(app: "node"))
    let plan = Planner.plan([it], running: notRunning)
    #expect(plan.skipped.first?.reason == "node is running. Quit node to clean web: node_modules.")
}

@Test func liveParsesLsof() async throws {
    try await withTempDirAsync { dir in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        p.currentDirectoryURL = dir
        try p.run()
        defer { p.terminate() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(DevProcessCheck(commands: ["sleep"]).runningIn(dir) == "sleep")
    }
}
