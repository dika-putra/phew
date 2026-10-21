import Foundation
import Testing
@testable import PhewCore

private func projectItem(_ root: String, _ artifact: String, pre: Bool) -> Item {
    let path = "\(root)/\(artifact)"
    let t = PathTarget(id: "projects:\(path)", group: "Projects", title: artifact, tier: .regenerates, paths: [path])
    var i = Item(id: t.id, target: t, urls: [], bytes: 1, lastUsed: nil, state: .ready)
    i.preselected = pre
    return i
}

private let items = [
    projectItem("/a/web", "node_modules", pre: true),
    projectItem("/a/web", ".next", pre: false),
    projectItem("/a/website", "node_modules", pre: false),
]

@Test func exactArtifactId() {
    let r = matchProjectItems(["projects:/a/web/.next"], in: items)
    #expect(r.matched.map(\.id) == ["projects:/a/web/.next"])
    #expect(r.unknown.isEmpty)
}

@Test func projectRootPrefixOnBoundary() {
    let r = matchProjectItems(["projects:/a/web"], in: items)
    #expect(r.matched.map(\.id) == ["projects:/a/web/node_modules", "projects:/a/web/.next"])
}

@Test func bareProjectsMeansPreselected() {
    #expect(matchProjectItems(["projects"], in: items).matched.map(\.id) == ["projects:/a/web/node_modules"])
}

@Test func unknownReported() {
    #expect(matchProjectItems(["projects:/nope"], in: items).unknown == ["projects:/nope"])
}
