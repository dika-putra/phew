import Foundation
import Testing
@testable import PhewApp
@testable import PhewCore

func appItem(_ id: String, bytes: Int64 = 10, tier: Tier = .regenerates, state: ItemState = .ready) -> Item {
    let t = PathTarget(id: id, group: "G", title: id.uppercased(), tier: tier, paths: ["~/\(id)"])
    return Item(id: id, target: t, urls: [], bytes: bytes, lastUsed: nil, state: state)
}

/// AppModel with no real notifications, config or UserDefaults.
@MainActor func makeModel(scan: @escaping @Sendable () async -> ScanSnapshot, cache: ScanCache,
                          available: @escaping @Sendable () -> Int64, running: RunningCheck = .live,
                          execute: @escaping @Sendable (CleanPlan, @escaping @Sendable (String) -> Void) async -> Receipt = { _, _ in
                              Receipt(entries: [], freeBefore: 0, freeAfter: 0) }) -> AppModel {
    AppModel(scan: scan, cache: cache, available: available, running: running, execute: execute,
             notify: { _ in }, alertSettings: { LowSpaceAlert(enabled: false, thresholdGB: 20) },
             defaults: UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!, reconcile: { $0 })
}

func tempCache() -> ScanCache {
    ScanCache(url: FileManager.default.temporaryDirectory.appending(path: "phew-app-\(UUID().uuidString)/scan.json"))
}

@MainActor @Test func loadsCacheOnInit() throws {
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a")], skippedProjects: 0, unreadable: []))
    let model = makeModel(scan: { fatalError("no scan") }, cache: cache, available: { 1 })
    #expect(model.snapshot?.items.map(\.id) == ["a"])
}

@MainActor @Test func refreshSavesCacheAndPreselects() async {
    let cache = tempCache()
    let items = [appItem("a"), appItem("b", tier: .dataLoss)]
    let model = makeModel(scan: { ScanSnapshot(date: .now, items: items, skippedProjects: 0, unreadable: []) },
                         cache: cache, available: { 5 })
    await model.refresh()
    #expect(cache.load()?.items.count == 2)
    #expect(model.selection == ["a"])
    #expect(model.available == 5)
    #expect(!model.isScanning)
}

actor Gate {
    var calls = 0
    var waiter: CheckedContinuation<Void, Never>?
    func enter() async { calls += 1; await withCheckedContinuation { waiter = $0 } }
    func open() { waiter?.resume(); waiter = nil }
}

@MainActor @Test func refreshIgnoredWhileScanning() async throws {
    let gate = Gate()
    let model = makeModel(scan: {
        await gate.enter()
        return ScanSnapshot(date: .now, items: [], skippedProjects: 0, unreadable: [])
    }, cache: tempCache(), available: { 1 })
    let first = Task { await model.refresh() }
    while await gate.calls == 0 { await Task.yield() }
    #expect(model.isScanning)
    await model.refresh()
    #expect(await gate.calls == 1)
    await gate.open()
    await first.value
    #expect(!model.isScanning)
}

private let quiet = RunningCheck(runningBundleIDs: { [:] }, processMatches: { _ in false })

@MainActor private func model(items: [Item], running: RunningCheck = quiet,
                              execute: @escaping @Sendable (CleanPlan, @escaping @Sendable (String) -> Void) async -> Receipt) throws -> AppModel {
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: items, skippedProjects: 0, unreadable: []))
    return makeModel(scan: { fatalError("no scan") }, cache: cache, available: { 1 }, running: running, execute: execute)
}

private func receipt(for plan: CleanPlan) -> Receipt {
    Receipt(entries: plan.items.map { ReceiptEntry(itemID: $0.id, title: $0.target.title, claimed: $0.bytes,
                                                   measured: $0.bytes, failures: [], skippedReason: nil) },
            freeBefore: 1, freeAfter: 2)
}

@MainActor @Test func confirmRunsExecutorAndShowsReceipt() async throws {
    let m = try model(items: [appItem("a")]) { plan, _ in receipt(for: plan) }
    m.selection = ["a"]
    m.cleanSelected(in: "G")
    guard case .confirm = m.screen else { Issue.record("expected confirm, got \(m.screen)"); return }
    m.confirm()
    await m.waitForClean()
    guard case .receipt(let r) = m.screen else { Issue.record("expected receipt"); return }
    #expect(r.measuredTotal == 10)
}

@MainActor @Test func inUseSelectedItemShowsReasonInConfirm() throws {
    let t = PathTarget(id: "dd", group: "Xcode", title: "DerivedData", tier: .regenerates, paths: ["~/dd"],
                       skipIfRunning: ["com.apple.dt.Xcode"])
    let it = Item(id: "dd", target: t, urls: [], bytes: 1, lastUsed: nil, state: .ready)
    let xcode = RunningCheck(runningBundleIDs: { ["com.apple.dt.Xcode": "Xcode"] }, processMatches: { _ in false })
    let m = try model(items: [it], running: xcode) { plan, _ in receipt(for: plan) }
    m.selection = ["dd"]
    m.cleanSelected(in: "Xcode")
    guard case .confirm(let plan) = m.screen else { Issue.record("expected confirm"); return }
    #expect(plan.items.isEmpty)
    #expect(plan.skipped.first?.reason == "Xcode is running. Quit Xcode to clean DerivedData.")
}

@MainActor @Test func cleanSurvivesScreenChange() async throws {
    let m = try model(items: [appItem("a")]) { plan, _ in
        try? await Task.sleep(for: .milliseconds(100))
        return receipt(for: plan)
    }
    m.selection = ["a"]
    m.cleanSelected(in: "G")
    m.confirm()
    m.screen = .home
    await m.waitForClean()
    #expect(m.lastReceipt != nil)
    if case .receipt = m.screen {} else { Issue.record("receipt not shown after clean") }
}

@MainActor @Test func cleanedItemsLeaveSnapshot() async throws {
    let m = try model(items: [appItem("a"), appItem("b")]) { plan, _ in receipt(for: plan) }
    m.selection = ["a"]
    m.cleanSelected(in: "G")
    m.confirm()
    await m.waitForClean()
    #expect(m.snapshot?.items.map(\.id) == ["b"])
    #expect(!m.selection.contains("a"))
}

@MainActor @Test func inUseItemsAreNotPreselected() async {
    let busy = appItem("busy", state: .inUse(app: "Gradle"))
    let m = makeModel(scan: { ScanSnapshot(date: .now, items: [appItem("a"), busy], skippedProjects: 0, unreadable: []) },
                     cache: tempCache(), available: { 1 })
    await m.refresh()
    #expect(m.selection == ["a"])
}

@MainActor private func projectItem(_ id: String, root: String, state: ItemState = .ready) -> Item {
    var i = appItem(id, state: state)
    i.project = ProjectInfo(root: URL(fileURLWithPath: root), name: "web", stacks: ["Node"], lastModified: nil, dormant: false)
    return i
}

@MainActor @Test func toggleProjectSelectsAllReadyItems() throws {
    let items = [projectItem("a", root: "/w"), projectItem("b", root: "/w"), projectItem("c", root: "/w", state: .inUse(app: "vite")),
                 projectItem("e", root: "/w", state: .unreadable), projectItem("d", root: "/other")]
    let m = try model(items: items) { plan, _ in receipt(for: plan) }
    m.selection = []
    m.toggleProject(URL(fileURLWithPath: "/w"))
    // In-use items can be picked; the confirm view then says why they are skipped.
    #expect(m.selection == ["a", "b", "c"])
    m.toggleProject(URL(fileURLWithPath: "/w"))
    #expect(m.selection.isEmpty)
}

@Test func revealUsesTargetFolderForContentsAndUrlsOtherwise() {
    let home = URL(fileURLWithPath: "/Users/t")
    let folder = PathTarget(id: "f", group: "G", title: "F", tier: .regenerates, paths: ["~/A", "~/B"])
    let plain = Item(id: "f", target: folder, urls: [URL(fileURLWithPath: "/Users/t/A")], bytes: 1, lastUsed: nil, state: .ready)
    #expect(Reveal.urls(for: plain, home: home).map(\.path) == ["/Users/t/A"])
    let contents = PathTarget(id: "c", group: "G", title: "C", tier: .regenerates, paths: ["~/Library/Caches"], contents: true)
    let many = Item(id: "c", target: contents, urls: (0..<50).map { URL(fileURLWithPath: "/Users/t/Library/Caches/\($0)") },
                    bytes: 1, lastUsed: nil, state: .ready)
    #expect(Reveal.urls(for: many, home: home).map(\.path) == ["/Users/t/Library/Caches"])
}


@MainActor @Test func quickCleanOpensConfirmForSafeItemsOnly() throws {
    let items = [appItem("a"), appItem("b", tier: .dataLoss), appItem("c", state: .inUse(app: "Xcode"))]
    let m = try model(items: items) { plan, _ in receipt(for: plan) }
    m.quickClean()
    guard case .confirm(let plan) = m.screen else { Issue.record("expected confirm"); return }
    #expect(plan.items.map(\.id) == ["a"])
}

@MainActor @Test func vanishedItemsLeaveSnapshot() async throws {
    let m = try model(items: [appItem("a"), appItem("b")]) { plan, _ in
        Receipt(entries: plan.items.map { ReceiptEntry(itemID: $0.id, title: "", claimed: $0.bytes, measured: 0,
                                                       failures: [], skippedReason: nil) }, freeBefore: 0, freeAfter: 0)
    }
    m.selection = ["a"]
    m.cleanSelected(in: "G")
    m.confirm()
    await m.waitForClean()
    #expect(m.snapshot?.items.map(\.id) == ["b"])
}

@MainActor @Test func refreshKeepsUserUnchecks() async throws {
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a"), appItem("b")], skippedProjects: 0, unreadable: []))
    let m = makeModel(scan: { ScanSnapshot(date: .now, items: [appItem("a"), appItem("b"), appItem("c")],
                                           skippedProjects: 0, unreadable: []) }, cache: cache, available: { 1 })
    m.toggle("a")
    await m.refresh()
    #expect(m.selection == ["b", "c"])
}

@MainActor @Test func cacheIsReconciledOnLoad() throws {
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a"), appItem("b")], skippedProjects: 0, unreadable: []))
    let m = AppModel(scan: { fatalError() }, cache: cache, available: { 1 }, notify: { _ in },
                     alertSettings: { LowSpaceAlert(enabled: false, thresholdGB: 20) },
                     defaults: UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!,
                     reconcile: { snap in var s = snap; s.items.removeAll { $0.id == "a" }; return s })
    #expect(m.snapshot?.items.map(\.id) == ["b"])
}

@MainActor @Test func refreshIgnoredWhileCleaning() async throws {
    let gate = Gate()
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a")], skippedProjects: 0, unreadable: []))
    let scans = Spy()
    let m = makeModel(scan: { scans.messages.append("scan"); return ScanSnapshot(date: .now, items: [], skippedProjects: 0, unreadable: []) },
                      cache: cache, available: { 1 }, execute: { plan, _ in
                          await gate.enter()
                          return Receipt(entries: [], freeBefore: 0, freeAfter: 0)
                      })
    m.selection = ["a"]
    m.cleanSelected(in: "G")
    m.confirm()
    while await gate.calls == 0 { await Task.yield() }
    await m.refresh()
    #expect(scans.messages.isEmpty)
    await gate.open()
    await m.waitForClean()
}

@MainActor @Test func alertWithoutReclaimable() throws {
    let spy = Spy()
    let m = AppModel(scan: { fatalError() }, cache: tempCache(), available: { 10_000_000_000 },
                     notify: { spy.messages.append($0) }, alertSettings: { LowSpaceAlert(enabled: true, thresholdGB: 20) },
                     defaults: UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!, reconcile: { $0 })
    m.checkSpace()
    #expect(spy.messages == ["Only 10 GB left."])
}

@MainActor @Test func startDockerReplacesInfoWithItems() async throws {
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a")], skippedProjects: 0, unreadable: [], dockerOffBytes: 4_800_000_000))
    let calls = Spy()
    let docker = Item(id: "docker.buildcache", target: PathTarget(id: "docker.buildcache", group: "Docker", title: "B",
                                                                   tier: .regenerates, paths: []),
                      urls: [], bytes: 5, lastUsed: nil, state: .ready)
    let m = AppModel(scan: { fatalError() }, cache: cache, available: { 1 }, notify: { _ in },
                     alertSettings: { LowSpaceAlert(enabled: false, thresholdGB: 20) },
                     defaults: UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!, reconcile: { $0 },
                     openDocker: { calls.messages.append("open") },
                     dockerScan: { calls.messages.count < 3 ? { calls.messages.append("poll"); return .off(diskBytes: 1) }() : .running([docker]) },
                     dockerPoll: .milliseconds(1))
    await m.startDocker()
    #expect(calls.messages.first == "open")
    #expect(m.snapshot?.dockerOffBytes == nil)
    #expect(m.snapshot?.items.map(\.id) == ["a", "docker.buildcache"])
}
