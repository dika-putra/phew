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
