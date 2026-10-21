import Foundation
import Testing
@testable import PhewApp
@testable import PhewCore

func appItem(_ id: String, bytes: Int64 = 10, tier: Tier = .regenerates, state: ItemState = .ready) -> Item {
    let t = PathTarget(id: id, group: "G", title: id.uppercased(), tier: tier, paths: ["~/\(id)"])
    return Item(id: id, target: t, urls: [], bytes: bytes, lastUsed: nil, state: state)
}

func tempCache() -> ScanCache {
    ScanCache(url: FileManager.default.temporaryDirectory.appending(path: "phew-app-\(UUID().uuidString)/scan.json"))
}

@MainActor @Test func loadsCacheOnInit() throws {
    let cache = tempCache()
    try cache.save(ScanSnapshot(date: .now, items: [appItem("a")], skippedProjects: 0, unreadable: []))
    let model = AppModel(scan: { fatalError("no scan") }, cache: cache, available: { 1 })
    #expect(model.snapshot?.items.map(\.id) == ["a"])
}

@MainActor @Test func refreshSavesCacheAndPreselects() async {
    let cache = tempCache()
    let items = [appItem("a"), appItem("b", tier: .dataLoss)]
    let model = AppModel(scan: { ScanSnapshot(date: .now, items: items, skippedProjects: 0, unreadable: []) },
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
    let model = AppModel(scan: {
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
    return AppModel(scan: { fatalError("no scan") }, cache: cache, available: { 1 }, running: running, execute: execute)
}

private func receipt(for plan: CleanPlan) -> Receipt {
    Receipt(entries: plan.items.map { ReceiptEntry(itemID: $0.id, title: $0.target.title, claimed: $0.bytes,
                                                   measured: $0.bytes, failures: [], skippedReason: nil) },
            freeBefore: 1, freeAfter: 2)
}

@MainActor @Test func confirmRunsExecutorAndShowsReceipt() async throws {
    let m = try model(items: [appItem("a")]) { plan, _ in receipt(for: plan) }
    m.cleanItem("a")
    guard case .confirm = m.screen else { Issue.record("expected confirm, got \(m.screen)"); return }
    m.confirm()
    await m.waitForClean()
    guard case .receipt(let r) = m.screen else { Issue.record("expected receipt"); return }
    #expect(r.measuredTotal == 10)
}

@MainActor @Test func inUseItemDoesNotOpenConfirm() throws {
    let t = PathTarget(id: "dd", group: "Xcode", title: "DerivedData", tier: .regenerates, paths: ["~/dd"],
                       skipIfRunning: ["com.apple.dt.Xcode"])
    let it = Item(id: "dd", target: t, urls: [], bytes: 1, lastUsed: nil, state: .ready)
    let xcode = RunningCheck(runningBundleIDs: { ["com.apple.dt.Xcode": "Xcode"] }, processMatches: { _ in false })
    let m = try model(items: [it], running: xcode) { plan, _ in receipt(for: plan) }
    m.screen = .group("Xcode")
    m.cleanItem("dd")
    #expect(m.screen == .group("Xcode"))
    #expect(m.inlineMessage == "Xcode is running. Quit Xcode to clean DerivedData.")
}

@MainActor @Test func cleanSurvivesScreenChange() async throws {
    let m = try model(items: [appItem("a")]) { plan, _ in
        try? await Task.sleep(for: .milliseconds(100))
        return receipt(for: plan)
    }
    m.cleanItem("a")
    m.confirm()
    m.screen = .home
    await m.waitForClean()
    #expect(m.lastReceipt != nil)
    if case .receipt = m.screen {} else { Issue.record("receipt not shown after clean") }
}

@MainActor @Test func cleanedItemsLeaveSnapshot() async throws {
    let m = try model(items: [appItem("a"), appItem("b")]) { plan, _ in receipt(for: plan) }
    m.cleanItem("a")
    m.confirm()
    await m.waitForClean()
    #expect(m.snapshot?.items.map(\.id) == ["b"])
    #expect(!m.selection.contains("a"))
}

@MainActor @Test func inUseItemsAreNotPreselected() async {
    let busy = appItem("busy", state: .inUse(app: "Gradle"))
    let m = AppModel(scan: { ScanSnapshot(date: .now, items: [appItem("a"), busy], skippedProjects: 0, unreadable: []) },
                     cache: tempCache(), available: { 1 })
    await m.refresh()
    #expect(m.selection == ["a"])
}
