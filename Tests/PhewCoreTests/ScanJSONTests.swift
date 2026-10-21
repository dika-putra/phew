import Foundation
import Testing
@testable import PhewCore

@Test func scanJSONShape() throws {
    let items = [item("a", bytes: 5), item("b", state: .inUse(app: "X")), item("c", state: .unreadable)]
    let data = try scanJSON(items, available: 123)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(root["version"] as? Int == 1)
    #expect(root["available"] as? Int == 123)
    let list = try #require(root["items"] as? [[String: Any]])
    #expect(Set(list[0].keys) == ["id", "group", "title", "tier", "flags", "bytes", "lastUsed", "state",
                                  "preselected", "paths"])
    #expect(list.map { $0["state"] as? String } == ["ready", "inUse", "unreadable"])
    #expect(list[0]["lastUsed"] is NSNull)
    #expect(list[0]["bytes"] as? Int == 5)
}

@Test func scanJSONIncludesProject() throws {
    var i = item("p", bytes: 1)
    i.project = ProjectInfo(root: URL(fileURLWithPath: "/a/web"), name: "web", stacks: ["Node"],
                            lastModified: nil, dormant: true)
    let root = try #require(JSONSerialization.jsonObject(with: try scanJSON([i], available: 0)) as? [String: Any])
    let p = try #require((root["items"] as? [[String: Any]])?.first?["project"] as? [String: Any])
    #expect(p["root"] as? String == "/a/web")
    #expect(p["name"] as? String == "web")
    #expect(p["stacks"] as? [String] == ["Node"])
    #expect(p["dormant"] as? Bool == true)
}
