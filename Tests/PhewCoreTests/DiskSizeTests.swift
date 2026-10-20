import Foundation
import Testing
@testable import PhewCore

private let MiB = 1_048_576

@Test func countsHiddenFiles() throws {
    try withTempDir { dir in
        try writeFile(dir.appending(path: ".hidden"), bytes: 65_536)
        #expect(DiskSize.allocated(dir).bytes >= 65_536)
    }
}

@Test func hardLinkCountedOnce() throws {
    try withTempDir { dir in
        let file = dir.appending(path: "a/file")
        try writeFile(file, bytes: MiB)
        try FileManager.default.linkItem(at: file, to: dir.appending(path: "a/link"))
        let bytes = DiskSize.allocated(dir).bytes
        #expect(bytes >= Int64(MiB))
        #expect(bytes < Int64(2 * MiB))
    }
}

@Test func symlinkTargetNotCounted() throws {
    try withTempDir { root in
        let outside = root.appending(path: "outside/big")
        try writeFile(outside, bytes: MiB)
        let dir = root.appending(path: "dir")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dir.appending(path: "link"), withDestinationURL: outside)
        #expect(DiskSize.allocated(dir).bytes < 65_536)
    }
}

@Test func missingPathIsZero() throws {
    try withTempDir { dir in
        #expect(DiskSize.allocated(dir.appending(path: "nope")) == SizeResult(bytes: 0, unreadable: []))
    }
}

@Test func unreadableFolderIsReported() throws {
    try withTempDir { dir in
        let locked = dir.appending(path: "locked")
        try writeFile(locked.appending(path: "f"), bytes: 65_536)
        try writeFile(dir.appending(path: "ok"), bytes: 65_536)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let result = DiskSize.allocated(dir)
        #expect(result.unreadable.map(\.lastPathComponent) == ["locked"])
        #expect(result.bytes >= 65_536)
    }
}

@Test func availableIsPositive() {
    #expect(DiskSize.available() > 0)
}
