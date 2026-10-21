import Foundation
import Testing
@testable import PhewCore

private let builtin = Catalog.all(custom: [])
private func target(_ id: String) -> PathTarget? { builtin.first { $0.id == id } }

@Test func idsAreUnique() {
    let ids = builtin.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test func coversSpecTable() {
    let expected = ["macos.caches", "macos.logs", "xcode.deriveddata", "xcode.archives", "xcode.devicesupport",
                    "xcode.caches", "xcode.previews", "swiftpm", "cocoapods", "gradle", "android.systemimages",
                    "android.avd", "dart.pubcache", "dart.analysis", "yarn", "bun", "browsers", "node-gyp",
                    "electron", "pip", "uv", "poetry", "conda.pkgs", "composer", "gem", "bundler", "maven",
                    "nuget", "go.buildcache", "brew", "orbstack",
                    "editors.vscode", "editors.cursor", "editors.windsurf", "editors.devin", "editors.zed",
                    "editors.jetbrains"]
    for id in expected { #expect(target(id) != nil, "missing \(id)") }
}

@Test func noBuiltinPathIsForbidden() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    for t in builtin {
        for p in t.paths {
            #expect(!PathGuard.isForbidden(expandTilde(p, home: home), home: home), "\(t.id): \(p)")
            #expect(p.hasPrefix("~/"), "\(t.id): \(p) should be under home")
        }
    }
}

@Test func tiersAndFlagsMatchSpec() {
    #expect(target("xcode.archives")?.tier == .dataLoss)
    #expect(target("android.avd")?.tier == .dataLoss)
    #expect(target("android.avd")?.flags.contains(.heavy) == true)
    #expect(target("xcode.devicesupport")?.flags.contains(.heavy) == true)
    #expect(target("android.systemimages")?.flags.contains(.heavy) == true)
    for id in ["maven", "nuget", "macos.caches"] { #expect(target(id)?.flags.contains(.optIn) == true, "\(id)") }
    #expect(target("xcode.deriveddata")?.skipIfRunning.contains("com.apple.dt.Xcode") == true)
    #expect(target("gradle")?.skipIfRunning.contains("proc:Gradle=GradleDaemon") == true)
    #expect(target("macos.caches")?.contents == true)
    #expect(target("macos.logs")?.contents == true)
}

@Test func editorTargetsOnlyTouchCacheFolders() {
    let allowed: Set<String> = ["Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache",
                                "DawnGraphiteCache", "DawnWebGPUCache", "logs"]
    for t in builtin where t.id.hasPrefix("editors.") && t.id != "editors.jetbrains" {
        for p in t.paths { #expect(allowed.contains((p as NSString).lastPathComponent), "\(p)") }
        #expect(!t.skipIfRunning.isEmpty, "\(t.id)")
    }
}

@Test func customTargetsAppended() {
    let all = Catalog.all(custom: [CustomTargetSpec(id: "custom.x", title: "X", paths: ["~/x"], tier: .redownload)])
    #expect(all.last?.id == "custom.x")
    #expect(all.last?.group == "Extra folders")
    #expect(all.last?.flags.isEmpty == true)
}
