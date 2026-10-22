import Foundation
import Testing
@testable import PhewApp
@testable import PhewCore

func appItem(_ id: String, bytes: Int64 = 10, tier: Tier = .regenerates, state: ItemState = .ready) -> Item {
    let t = PathTarget(id: id, group: "G", title: id.uppercased(), tier: tier, paths: ["~/\(id)"])
    return Item(id: id, target: t, urls: [], bytes: bytes, lastUsed: nil, state: state)
}

/// AppModel with no real notifications, config or UserDefaults.
@MainActor func makeModel(scan: @escaping @Sendable (@escaping @Sendable (String) -> Void) async -> ScanSnapshot, cache: ScanCache,
                          available: @escaping @Sendable () -> Int64, running: RunningCheck = .live,
                          execute: @escaping @Sendable (CleanPlan, @escaping @Sendable (String) -> Void) async -> Receipt = { _, _ in
                              Receipt(entries: [], freeBefore: 0, freeAfter: 0) },
                          defaults: UserDefaults = UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!) -> AppModel {
    AppModel(scan: scan, cache: cache, available: available, running: running, execute: execute,
             notify: { _ in }, alertSettings: { LowSpaceAlert(enabled: false, thresholdGB: 20) },
             defaults: defaults, reconcile: { $0 })
}

func tempCache() -> ScanCache {
    ScanCache(url: FileManager.default.temporaryDirectory.appending(path: "phew-app-\(UUID().uuidString)/scan.json"))
}

@MainActor @Test func loadsCacheOnInit() throws {
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a")], skippedProjects: 0, unreadable: []))
    let model = makeModel(scan: { _ in fatalError("no scan") }, cache: cache, available: { 1 })
    #expect(model.snapshot?.items.map(\.id) == ["a"])
}

@MainActor @Test func refreshSavesCacheAndPreselects() async {
    let cache = tempCache()
    let items = [appItem("a"), appItem("b", tier: .dataLoss)]
    let model = makeModel(scan: { _ in ScanSnapshot(date: .now, items: items, skippedProjects: 0, unreadable: []) },
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
    let model = makeModel(scan: { _ in
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
    return makeModel(scan: { _ in fatalError("no scan") }, cache: cache, available: { 1 }, running: running, execute: execute)
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
    let m = makeModel(scan: { _ in ScanSnapshot(date: .now, items: [appItem("a"), busy], skippedProjects: 0, unreadable: []) },
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
    let m = makeModel(scan: { _ in ScanSnapshot(date: .now, items: [appItem("a"), appItem("b"), appItem("c")],
                                           skippedProjects: 0, unreadable: []) }, cache: cache, available: { 1 })
    m.toggle("a")
    await m.refresh()
    #expect(m.selection == ["b", "c"])
}

@MainActor @Test func cacheIsReconciledOnLoad() throws {
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a"), appItem("b")], skippedProjects: 0, unreadable: []))
    let m = AppModel(scan: { _ in fatalError() }, cache: cache, available: { 1 }, notify: { _ in },
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
    let m = makeModel(scan: { _ in scans.messages.append("scan"); return ScanSnapshot(date: .now, items: [], skippedProjects: 0, unreadable: []) },
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
    let m = AppModel(scan: { _ in fatalError() }, cache: tempCache(), available: { 10_000_000_000 },
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
    let m = AppModel(scan: { _ in fatalError() }, cache: cache, available: { 1 }, notify: { _ in },
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

@MainActor @Test func partialFailureKeepsRemovalAndNote() async throws {
    var tool = appItem("pnpm", bytes: 100)
    tool.removal = .steps([.run(["pnpm", "store", "prune"])])
    tool.measure = .docker
    tool.note = "Used by web"
    let m = try model(items: [tool]) { plan, _ in
        Receipt(entries: [ReceiptEntry(itemID: "pnpm", title: "", claimed: 100, measured: 40, failures: ["boom"], skippedReason: nil)],
                freeBefore: 0, freeAfter: 0)
    }
    m.selection = ["pnpm"]
    m.cleanSelected(in: "G")
    m.confirm()
    await m.waitForClean()
    let kept = try #require(m.snapshot?.items.first)
    #expect(kept.bytes == 60)
    #expect(kept.removal == tool.removal && kept.measure == .docker && kept.note == "Used by web")
}

// M5.5

private func sized(_ id: String, _ bytes: Int64, state: ItemState = .ready) -> Item { appItem(id, bytes: bytes, state: state) }

@MainActor @Test func groupItemsSortedBySize() throws {
    let m = try model(items: [sized("s", 1), sized("l", 30), sized("m", 20)]) { plan, _ in receipt(for: plan) }
    #expect(m.items(in: "G").map(\.id) == ["l", "m", "s"])
}

@MainActor @Test func toggleAllSkipsLockedAndUnreadable() throws {
    let items = [sized("a", 1), sized("b", 1, state: .locked("default")), sized("c", 1, state: .unreadable)]
    let m = try model(items: items) { plan, _ in receipt(for: plan) }
    m.selection = []
    m.toggleAll(m.items(in: "G"))
    #expect(m.selection == ["a"])
    #expect(m.selectionState(m.items(in: "G")) == .on)
    m.toggleAll(m.items(in: "G"))
    #expect(m.selection.isEmpty)
}

@MainActor @Test func selectionStateOfUnselectableGroupIsOff() throws {
    let m = try model(items: [sized("b", 1, state: .locked("default"))]) { plan, _ in receipt(for: plan) }
    #expect(m.selectionState(m.items(in: "G")) == .off)
}

@MainActor @Test func selectionStateMixed() throws {
    let m = try model(items: [sized("a", 1), sized("b", 1)]) { plan, _ in receipt(for: plan) }
    m.selection = ["a"]
    #expect(m.selectionState(m.items(in: "G")) == .mixed)
}

@MainActor @Test func untickingPreselectedItemKeepsIt() async {
    let defaults = UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!
    let scan: @Sendable (@escaping @Sendable (String) -> Void) async -> ScanSnapshot = { _ in
        ScanSnapshot(date: .now, items: [appItem("a")], skippedProjects: 0, unreadable: [])
    }
    let m = makeModel(scan: scan, cache: tempCache(), available: { 1 }, defaults: defaults)
    await m.refresh()
    m.toggle("a")
    #expect(m.kept == ["a"])
    let again = makeModel(scan: scan, cache: tempCache(), available: { 1 }, defaults: defaults)
    await again.refresh()
    #expect(again.selection.isEmpty)
    #expect(again.summary.reclaimable == 0)
    again.toggle("a")
    #expect(again.kept.isEmpty)
}

@MainActor @Test func keptSurvivesItemDisappearing() async {
    let present = Spy()
    present.messages = ["a"]
    let m = makeModel(scan: { _ in
        ScanSnapshot(date: .now, items: present.messages.map { appItem($0) }, skippedProjects: 0, unreadable: [])
    }, cache: tempCache(), available: { 1 })
    await m.refresh()
    m.toggle("a")
    present.messages = []
    await m.refresh()
    present.messages = ["a"]
    await m.refresh()
    #expect(m.selection.isEmpty)
}

@MainActor @Test func keptTitleFallsBackToID() throws {
    let m = try model(items: [appItem("a")]) { plan, _ in receipt(for: plan) }
    #expect(m.keptTitle("a") == "A")
    #expect(m.keptTitle("gone") == "gone")
}

@MainActor @Test func lastCleanRecordedAfterClean() async throws {
    let defaults = UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a", bytes: 40)], skippedProjects: 0, unreadable: []))
    let m = makeModel(scan: { _ in fatalError() }, cache: cache, available: { 1 },
                      execute: { plan, _ in receipt(for: plan) }, defaults: defaults)
    m.selection = ["a"]
    m.cleanSelected(in: "G")
    m.confirm()
    await m.waitForClean()
    #expect(m.lastClean?.freed == 40)
    let again = makeModel(scan: { _ in fatalError() }, cache: tempCache(), available: { 1 }, defaults: defaults)
    #expect(again.lastClean?.freed == 40)
}

@MainActor @Test func lastCleanNotRecordedWhenNothingFreed() async throws {
    let m = try model(items: [appItem("a")]) { _, _ in Receipt(entries: [], freeBefore: 0, freeAfter: 0) }
    m.selection = ["a"]
    m.cleanSelected(in: "G")
    m.confirm()
    await m.waitForClean()
    #expect(m.lastClean == nil)
}

@MainActor @Test func scanStageShownWhileScanning() async {
    let gate = Gate()
    let m = makeModel(scan: { progress in
        progress("Project folders")
        await gate.enter()
        return ScanSnapshot(date: .now, items: [], skippedProjects: 0, unreadable: [])
    }, cache: tempCache(), available: { 1 })
    let task = Task { await m.refresh() }
    while await gate.calls == 0 { await Task.yield() }
    // The stage is set on the main actor; let that hop run.
    for _ in 0..<10 where m.scanStage == nil { await Task.yield() }
    #expect(m.scanStage == "Project folders")
    await gate.open()
    await task.value
    #expect(m.scanStage == nil)
}

// M5.5 review fixes

@MainActor @Test func itemTurningReadyIsSelected() async {
    let busy = Spy()
    busy.messages = ["busy"]
    let m = makeModel(scan: { _ in
        ScanSnapshot(date: .now, items: [appItem("a", state: busy.messages.isEmpty ? .ready : .inUse(app: "Gradle"))],
                     skippedProjects: 0, unreadable: [])
    }, cache: tempCache(), available: { 1 })
    await m.refresh()
    #expect(m.selection.isEmpty)
    busy.messages = []
    await m.refresh()
    #expect(m.selection == ["a"])
    #expect(m.summary.quickClean.map(\.id) == ["a"])
}

@MainActor @Test func clearingGroupKeepsItsPreselectedItems() throws {
    let m = try model(items: [appItem("a"), appItem("b", tier: .dataLoss)]) { plan, _ in receipt(for: plan) }
    m.selection = ["a", "b"]
    m.toggleAll(m.items(in: "G"))
    #expect(m.kept == ["a"])
}

@MainActor @Test func startDockerRespectsKept() async throws {
    let cache = tempCache()
    let docker = Item(id: "docker.buildcache", target: PathTarget(id: "docker.buildcache", group: "Docker", title: "B",
                                                                   tier: .regenerates, paths: []),
                      urls: [], bytes: 5, lastUsed: nil, state: .ready)
    try cache.save(ScanSnapshot(date: .now, items: [docker], skippedProjects: 0, unreadable: []))
    let defaults = UserDefaults(suiteName: "phew-test-\(UUID().uuidString)")!
    defaults.set(["docker.buildcache"], forKey: "keptItems")
    let m = AppModel(scan: { _ in fatalError() }, cache: cache, available: { 1 }, notify: { _ in },
                     alertSettings: { LowSpaceAlert(enabled: false, thresholdGB: 20) }, defaults: defaults,
                     reconcile: { $0 }, openDocker: {}, dockerScan: { .running([docker]) }, dockerPoll: .milliseconds(1))
    await m.startDocker()
    #expect(m.selection.isEmpty)
}
