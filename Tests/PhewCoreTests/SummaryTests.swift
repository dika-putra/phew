import Foundation
import Testing
@testable import PhewCore

private func gi(_ id: String, _ group: String, _ bytes: Int64, tier: Tier = .regenerates, flags: Set<Flag> = [],
                state: ItemState = .ready) -> Item {
    let t = PathTarget(id: id, group: group, title: id, tier: tier, flags: flags, paths: ["~/\(id)"])
    return Item(id: id, target: t, urls: [], bytes: bytes, lastUsed: nil, state: state)
}

@Test func tierTotals() {
    let s = Summary([gi("a", "X", 10), gi("b", "X", 20, tier: .redownload), gi("c", "Y", 5, tier: .dataLoss)])
    #expect(s.byTier[.regenerates] == 10 && s.byTier[.redownload] == 20 && s.byTier[.dataLoss] == 5)
    #expect(s.total == 35)
}

@Test func reclaimableEqualsPreselectedReadyItems() {
    var active = gi("p", "Projects", 640)
    active.preselected = false
    let s = Summary([gi("a", "X", 10), gi("h", "X", 320, flags: [.heavy]), active])
    #expect(s.reclaimable == 10)
    #expect(s.quickClean.map(\.id) == ["a"])
}

@Test func reclaimableExcludesDataLossOptInAndInUse() {
    let s = Summary([gi("a", "X", 10), gi("b", "X", 20, tier: .dataLoss), gi("c", "X", 40, flags: [.optIn]),
                     gi("d", "X", 80, state: .inUse(app: "Xcode")), gi("e", "X", 160, state: .unreadable)])
    #expect(s.reclaimable == 10)
}

@Test func groupsSortedAndEmptyDropped() {
    let s = Summary([gi("a", "Small", 1), gi("b", "Big", 100), gi("c", "Empty", 0)])
    #expect(s.groups.map(\.id) == ["Big", "Small"])
}

@Test func projectGroupsSplitSmallItems() {
    func pi(_ id: String, _ root: String, _ bytes: Int64) -> Item {
        var i = gi(id, "Projects", bytes)
        i.project = ProjectInfo(root: URL(fileURLWithPath: root), name: root, stacks: [], lastModified: nil, dormant: false)
        return i
    }
    let groups = projectGroups([pi("a", "/p1", 5_000_000), pi("b", "/p1", 8_000), pi("c", "/p2", 50_000_000)])
    #expect(groups.map(\.id.path) == ["/p2", "/p1"])
    #expect(groups[1].items.map(\.id) == ["a"])
    #expect(groups[1].small.map(\.id) == ["b"])
    #expect(groups[1].bytes == 5_008_000)
}
