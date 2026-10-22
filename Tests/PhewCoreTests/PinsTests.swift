import Foundation
import Testing
@testable import PhewCore

private func write(_ root: URL, _ files: [String: String]) throws {
    for (path, content) in files {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

@Test func fvmrcAndLegacyCountOnce() throws {
    try withTempDir { dir in
        try write(dir, ["app/.fvmrc": #"{"flutter": "3.24.5"}"#,
                        "app/.fvm/fvm_config.json": #"{"flutterSdkVersion": "3.24.5"}"#,
                        "other/.fvmrc": #"{"flutter": "3.47.0"}"#])
        let pins = PinFinder.find(roots: [dir])
        #expect(pins.flutter["3.24.5"]?.map(\.lastPathComponent) == ["app"])
        #expect(pins.flutter["3.47.0"]?.count == 1)
    }
}

@Test func nvmrcPrefixMatch() throws {
    try withTempDir { dir in
        try write(dir, ["web/.nvmrc": "v20\n"])
        let pins = PinFinder.find(roots: [dir])
        #expect(pins.node["20"]?.count == 1)
    }
    #expect(nodePinMatches("20", "v20.11.0"))
    #expect(nodePinMatches("v20.11", "20.11.0"))
    #expect(!nodePinMatches("20", "200.1.0"))
    #expect(!nodePinMatches("lts/*", "20.11.0"))
    #expect(!nodePinMatches("20.1", "20.11.0"))
}

@Test func rustToolchainTomlAndPlain() throws {
    try withTempDir { dir in
        try write(dir, ["a/rust-toolchain.toml": "[toolchain]\nchannel = \"1.79.0\"\n", "b/rust-toolchain": "nightly\n"])
        let pins = PinFinder.find(roots: [dir])
        #expect(pins.rust["1.79.0"]?.count == 1)
        #expect(pins.rust["nightly"]?.count == 1)
    }
}

@Test func prunedFoldersIgnored() throws {
    try withTempDir { dir in
        try write(dir, ["app/node_modules/dep/.nvmrc": "18"])
        #expect(PinFinder.find(roots: [dir]).node.isEmpty)
    }
}
