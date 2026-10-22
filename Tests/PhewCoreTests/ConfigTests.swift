import Foundation
import Testing
@testable import PhewCore

private let fakeHome = URL(fileURLWithPath: "/Users/phew-test")

@Test func missingFileCreatesDefaults() throws {
    try withTempDir { dir in
        let file = dir.appending(path: "phew/config.json")
        let loaded = ConfigStore(url: file, home: fakeHome).load()
        #expect(loaded.config == PhewConfig())
        #expect(loaded.issues.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}

@Test func defaultsMatchSpec() {
    let c = PhewConfig()
    #expect(c.version == 1 && c.projectRoots.isEmpty && c.dormantDays == 14)
    #expect(c.lowSpaceAlert == LowSpaceAlert(enabled: true, thresholdGB: 20))
}

@Test func malformedFileKeepsUserFile() throws {
    try withTempDir { dir in
        let file = dir.appending(path: "config.json")
        try "{ not json".write(to: file, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(url: file, home: fakeHome).load()
        #expect(loaded.config == PhewConfig())
        #expect(loaded.issues.count == 1)
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ not json")
    }
}

@Test func missingKeysFallBackToDefaults() throws {
    try withTempDir { dir in
        let file = dir.appending(path: "config.json")
        try #"{ "dormantDays": 30 }"#.write(to: file, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(url: file, home: fakeHome).load()
        #expect(loaded.config.dormantDays == 30)
        #expect(loaded.config.lowSpaceAlert.thresholdGB == 20)
        #expect(loaded.issues.isEmpty)
    }
}

@Test func roundTrip() throws {
    try withTempDir { dir in
        let store = ConfigStore(url: dir.appending(path: "config.json"), home: fakeHome)
        var c = PhewConfig()
        c.projectRoots = ["/Users/phew-test/Projects"]
        c.lowSpaceAlert = LowSpaceAlert(enabled: false, thresholdGB: 50)
        try store.save(c)
        #expect(store.load().config == c)
    }
}

@Test func invalidCustomTargetsSkipped() throws {
    try withTempDir { dir in
        let store = ConfigStore(url: dir.appending(path: "config.json"), home: fakeHome)
        var c = PhewConfig()
        let valid = CustomTargetSpec(id: "custom.unity", title: "Unity", paths: ["~/Library/Unity/cache"], tier: .redownload)
        c.customTargets = [
            CustomTargetSpec(id: "custom.a", title: "A", paths: ["~"], tier: .regenerates),
            CustomTargetSpec(id: "custom.b", title: "B", paths: ["/"], tier: .regenerates),
            CustomTargetSpec(id: "custom.c", title: "C", paths: ["/Users"], tier: .regenerates),
            CustomTargetSpec(id: "custom.d", title: "D", paths: [""], tier: .regenerates),
            CustomTargetSpec(id: "custom.e", title: "E", paths: [], tier: .regenerates),
            CustomTargetSpec(id: "custom.f", title: "F", paths: ["~other/x"], tier: .regenerates),
            CustomTargetSpec(id: "unity", title: "No prefix", paths: ["~/x"], tier: .regenerates),
            valid,
        ]
        try store.save(c)
        let loaded = store.load()
        #expect(loaded.validTargets == [valid])
        #expect(loaded.issues.count == 7)
    }
}

@Test func symlinkedRootStoredResolved() throws {
    try withTempDir { dir in
        let real = dir.appending(path: "real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = dir.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let store = ConfigStore(url: dir.appending(path: "config.json"), home: fakeHome)
        try store.addProjectRoot(link)
        try store.addProjectRoot(link)
        #expect(store.load().config.projectRoots == [real.path])
    }
}

@Test func expandsTilde() {
    #expect(expandTilde("~", home: fakeHome).path == "/Users/phew-test")
    #expect(expandTilde("~/a/b", home: fakeHome).path == "/Users/phew-test/a/b")
    #expect(expandTilde("/opt/x", home: fakeHome).path == "/opt/x")
}

@Test func removeProjectRoot() throws {
    try withTempDir { dir in
        let a = dir.appending(path: "a"), b = dir.appending(path: "b")
        for d in [a, b] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        let store = ConfigStore(url: dir.appending(path: "config.json"), home: fakeHome)
        try store.addProjectRoot(a)
        try store.addProjectRoot(b)
        try store.removeProjectRoot(a)
        #expect(store.load().config.projectRoots == [b.path])
    }
}

@Test func updateChangesOneSettingAndKeepsMalformedFile() throws {
    try withTempDir { dir in
        let file = dir.appending(path: "config.json")
        let store = ConfigStore(url: file, home: fakeHome)
        try store.update { $0.dormantDays = 30 }
        #expect(store.load().config.dormantDays == 30)
        try "{ bad".write(to: file, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try store.update { $0.dormantDays = 1 } }
        #expect(try String(contentsOf: file, encoding: .utf8) == "{ bad")
    }
}

/// Custom targets are preselected and join Quick clean, so they may only point inside the home
/// folder, and never into ~/.config (tokens, Phew's own config).
@Test func customTargetsStayInsideHome() throws {
    try withTempDir { dir in
        let store = ConfigStore(url: dir.appending(path: "config.json"), home: fakeHome)
        var c = PhewConfig()
        let inside = CustomTargetSpec(id: "custom.ok", title: "OK", paths: ["/Users/phew-test/.mytool/cache"], tier: .regenerates)
        c.customTargets = [
            CustomTargetSpec(id: "custom.apps", title: "Apps", paths: ["/Applications"], tier: .regenerates),
            CustomTargetSpec(id: "custom.usr", title: "Usr", paths: ["/usr/local/lib"], tier: .regenerates),
            CustomTargetSpec(id: "custom.brew", title: "Brew", paths: ["/opt/homebrew"], tier: .regenerates),
            CustomTargetSpec(id: "custom.gh", title: "gh", paths: ["~/.config/gh"], tier: .regenerates),
            inside,
        ]
        try store.save(c)
        let loaded = store.load()
        #expect(loaded.validTargets == [inside])
        #expect(loaded.issues.count == 4)
    }
}
