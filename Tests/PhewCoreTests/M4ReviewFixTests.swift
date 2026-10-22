import Foundation
import Testing
@testable import PhewCore

private func projectItem(_ root: String, state: ItemState = .ready) -> Item {
    let path = "\(root)/.next"
    let t = PathTarget(id: "projects:\(path)", group: "Projects", title: "web: .next", tier: .regenerates, paths: [path])
    var i = Item(id: t.id, target: t, urls: [], bytes: 1, lastUsed: nil, state: state)
    i.project = ProjectInfo(root: URL(fileURLWithPath: root), name: "web", stacks: ["Node"], lastModified: nil, dormant: true)
    return i
}

private func dev(_ cwd: String?) -> DevProcessCheck {
    DevProcessCheck(workingDirectories: { cwd.map { [(name: "next dev", cwd: $0)] } ?? [] })
}

@Test func plannerRechecksDevServerNow() {
    let plan = Planner.plan([projectItem("/a/web")], running: notRunning, devProcesses: dev("/a/web"))
    #expect(plan.skipped.first?.reason == "next dev is running. Quit next dev to clean web: .next.")
}

@Test func plannerIgnoresStaleInUseState() {
    let plan = Planner.plan([projectItem("/a/web", state: .inUse(app: "vite"))], running: notRunning, devProcesses: dev(nil))
    #expect(plan.items.count == 1)
}

@Test func flutterRunRealCommandLine() {
    let line = "/Users/u/fvm/versions/3.24.5/bin/cache/dart-sdk/bin/dart --disable-dart-dev --packages=/Users/u/fvm/versions/3.24.5/packages/flutter_tools/.dart_tool/package_config.json /Users/u/fvm/versions/3.24.5/bin/cache/flutter_tools.snapshot run -d macos"
    #expect(devServerName(line) == "flutter run")
}

@Test func reconcileRefreshesTargetsAndDropsStale() {
    let old = PathTarget(id: "x", group: "G", title: "Old", tier: .regenerates, paths: ["~/x"])
    let new = PathTarget(id: "x", group: "G", title: "New", tier: .dataLoss, paths: ["~/x"])
    let gone = PathTarget(id: "gone", group: "G", title: "Gone", tier: .regenerates, paths: ["~/g"])
    let items = [Item(id: "x", target: old, urls: [], bytes: 5, lastUsed: nil, state: .ready),
                 Item(id: "gone", target: gone, urls: [], bytes: 5, lastUsed: nil, state: .ready),
                 projectItem("/keep/web"), projectItem("/removed/web")]
    let snap = ScanSnapshot(date: .now, items: items, skippedProjects: 0, unreadable: [])
    let r = snap.reconciled(targets: [new], projectRoots: [URL(fileURLWithPath: "/keep")])
    #expect(r.items.map(\.id) == ["x", "projects:/keep/web/.next"])
    #expect(r.items[0].target.tier == .dataLoss)
    #expect(!r.items[0].preselected)
}

@Test func reconcileKeepsToolItems() {
    func tool(_ id: String) -> Item {
        Item(id: id, target: PathTarget(id: id, group: "Versions", title: id, tier: .redownload, paths: []),
             urls: [], bytes: 1, lastUsed: nil, state: .ready)
    }
    let ids = ["npm", "pnpm", "go.modcache", "cargo.registry", "docker.images", "ios.runtimes:U", "ios.dyld:/x", "nvm:v16", "fvm:3.24.5", "rustup:stable"]
    let snap = ScanSnapshot(date: .now, items: ids.map(tool), skippedProjects: 0, unreadable: [])
    #expect(snap.reconciled(targets: [], projectRoots: []).items.map(\.id) == ids)
}
