import Foundation
import Testing
@testable import PhewCore

func item(_ id: String, bytes: Int64 = 10, tier: Tier = .regenerates, skip: [String] = [],
          title: String? = nil, state: ItemState = .ready) -> Item {
    let t = PathTarget(id: id, group: "Test", title: title ?? id.uppercased(), tier: tier,
                       paths: ["~/\(id)"], skipIfRunning: skip)
    return Item(id: id, target: t, urls: [], bytes: bytes, lastUsed: nil, state: state)
}

@Test func inUseItemsAreSkippedWithMessage() {
    let running = RunningCheck(runningBundleIDs: { ["com.apple.dt.Xcode": "Xcode"] }, processMatches: { _ in false })
    let plan = Planner.plan([item("dd", skip: ["com.apple.dt.Xcode"], title: "DerivedData")], running: running)
    #expect(plan.items.isEmpty)
    #expect(plan.skipped.first?.reason == "Xcode is running. Quit Xcode to clean DerivedData.")
}

@Test func expectedBytesSumsPlannedOnly() {
    let running = RunningCheck(runningBundleIDs: { ["com.x": "X"] }, processMatches: { _ in false })
    let plan = Planner.plan([item("a", bytes: 10), item("b", bytes: 20), item("c", bytes: 99, skip: ["com.x"])],
                            running: running)
    #expect(plan.expectedBytes == 30)
    #expect(plan.items.map(\.id) == ["a", "b"])
}

@Test func flagsDataLoss() {
    #expect(Planner.plan([item("a", tier: .dataLoss)], running: notRunning).hasDataLoss)
    #expect(!Planner.plan([item("a")], running: notRunning).hasDataLoss)
}

@Test func unreadableItemsAreSkipped() {
    let plan = Planner.plan([item("a", title: "A", state: .unreadable)], running: notRunning)
    #expect(plan.skipped.first?.reason == "Can't read A. Grant Full Disk Access or check permissions.")
}
