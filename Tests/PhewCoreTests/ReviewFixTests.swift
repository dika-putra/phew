import Foundation
import Testing
@testable import PhewCore

private let fakeHome = URL(fileURLWithPath: "/Users/phew-test")

@Test func addProjectRootKeepsMalformedFile() throws {
    try withTempDir { dir in
        let file = dir.appending(path: "config.json")
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try ConfigStore(url: file, home: fakeHome).addProjectRoot(dir) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ not json")
    }
}

@Test func badCustomTargetEntryKeepsRestOfConfig() throws {
    try withTempDir { dir in
        let file = dir.appending(path: "config.json")
        let json = #"""
        { "dormantDays": 30, "projectRoots": ["/Users/phew-test/P"],
          "customTargets": [
            { "id": "custom.bad", "title": "Bad", "paths": ["~/x"], "tier": "nope" },
            { "id": "custom.notitle", "paths": ["~/y"], "tier": "redownload" },
            { "id": "custom.ok", "title": "Ok", "paths": ["~/z"], "tier": "redownload" } ] }
        """#
        try json.write(to: file, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(url: file, home: fakeHome).load()
        #expect(loaded.config.dormantDays == 30)
        #expect(loaded.config.projectRoots == ["/Users/phew-test/P"])
        #expect(loaded.validTargets.map(\.id) == ["custom.ok"])
        #expect(loaded.issues.count == 2)
    }
}

@Test func forbiddenCheckIgnoresCase() {
    #expect(PathGuard.isForbidden(URL(fileURLWithPath: "/USERS"), home: fakeHome))
    #expect(PathGuard.isForbidden(URL(fileURLWithPath: "/users/PHEW-TEST"), home: fakeHome))
    #expect(PathGuard.isForbidden(URL(fileURLWithPath: "/system/x"), home: fakeHome))
}

@Test func customTargetSymlinkToHomeRejected() throws {
    try withTempDir { tmp in
        let home = tmp.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appending(path: "link"), withDestinationURL: home)
        let store = ConfigStore(url: tmp.appending(path: "config.json"), home: home)
        var c = PhewConfig()
        c.customTargets = [CustomTargetSpec(id: "custom.l", title: "L", paths: ["~/link"], tier: .regenerates)]
        try store.save(c)
        #expect(store.load().validTargets.isEmpty)
    }
}

@Test func forbiddenRootIsDroppedFromGuard() throws {
    try withTempDir { tmp in
        let home = tmp.appending(path: "home")
        let docs = home.appending(path: "Documents")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        let rootLink = tmp.appending(path: "rootlink")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: home)
        let guard_ = PathGuard(allowedRoots: [rootLink], home: home)
        #expect(throws: PathGuardError.self) { try guard_.check(docs) }
    }
}

@Test func addProjectRootRefusesForbidden() throws {
    try withTempDir { tmp in
        let home = tmp.appending(path: "home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = ConfigStore(url: tmp.appending(path: "config.json"), home: home)
        #expect(throws: (any Error).self) { try store.addProjectRoot(home) }
        #expect(throws: (any Error).self) { try store.addProjectRoot(URL(fileURLWithPath: "/")) }
        #expect(store.load().config.projectRoots.isEmpty)
    }
}

@Test func missingParentFailsClosed() throws {
    try withTempDir { tmp in
        let root = tmp.appending(path: "root")
        let outside = tmp.appending(path: "outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: outside)
        let guard_ = PathGuard(allowedRoots: [root], home: tmp.appending(path: "home"))
        #expect(throws: PathGuardError.self) { try guard_.check(root.appending(path: "link/missing/x")) }
    }
}
