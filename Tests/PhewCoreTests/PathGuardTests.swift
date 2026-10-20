import Foundation
import Testing
@testable import PhewCore

private func setup(_ body: (URL, URL, PathGuard) throws -> Void) throws {
    try withTempDir { tmp in
        let home = tmp.appending(path: "home")
        let root = home.appending(path: "Library/Caches")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body(home, root, PathGuard(allowedRoots: [root], home: home))
    }
}

@Test func allowsPathInsideRoot() throws {
    try setup { _, root, guard_ in
        try FileManager.default.createDirectory(at: root.appending(path: "a"), withIntermediateDirectories: true)
        try guard_.check(root.appending(path: "a/b"))
    }
}

@Test func allowsRootItself() throws {
    try setup { _, root, guard_ in try guard_.check(root) }
}

@Test func refusesHomeAndRootAndAncestors() throws {
    try setup { home, _, guard_ in
        for url in [home, URL(fileURLWithPath: "/"), home.deletingLastPathComponent()] {
            #expect(throws: PathGuardError.forbidden(url.standardizedFileURL.path)) { try guard_.check(url) }
        }
    }
}

@Test func refusesSystemAndLibrary() throws {
    try setup { home, _, guard_ in
        #expect(throws: PathGuardError.forbidden("/System/Library")) { try guard_.check(URL(fileURLWithPath: "/System/Library")) }
        #expect(throws: PathGuardError.forbidden("/Library/Caches")) { try guard_.check(URL(fileURLWithPath: "/Library/Caches")) }
        #expect(!PathGuard.isForbidden(URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld"), home: home))
    }
}

@Test func refusesDotDotEscape() throws {
    try setup { home, root, guard_ in
        let url = root.appending(path: "a/../../x")
        #expect(throws: PathGuardError.outsideRoots(home.appending(path: "Library/x").path)) { try guard_.check(url) }
    }
}

@Test func refusesSymlinkedParentEscape() throws {
    try setup { home, root, guard_ in
        let outside = home.appending(path: "Documents")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: outside)
        #expect(throws: PathGuardError.escapesRoot(root.appending(path: "link/file").path)) {
            try guard_.check(root.appending(path: "link/file"))
        }
    }
}

@Test func allowsSymlinkAsLastComponent() throws {
    try setup { home, root, guard_ in
        try FileManager.default.createSymbolicLink(at: root.appending(path: "link"), withDestinationURL: home)
        try guard_.check(root.appending(path: "link"))
    }
}

@Test func siblingWithSharedPrefixIsOutside() throws {
    try setup { home, _, guard_ in
        let url = home.appending(path: "Library/CachesOther/x")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(throws: PathGuardError.outsideRoots(url.path)) { try guard_.check(url) }
    }
}
