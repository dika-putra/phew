// Path list adapted in part from PureMac (MIT), cli/Sources/puremac/Core/Catalog.swift.
// https://github.com/momenbasel/PureMac

private let xcode = "com.apple.dt.Xcode"
private let androidStudio = "com.google.android.studio"

private let editorCacheFolders = [
    "Cache", "CachedData", "CachedExtensionVSIXs", "Code Cache", "GPUCache",
    "DawnGraphiteCache", "DawnWebGPUCache", "logs",
]

private func editor(_ id: String, _ title: String, folder: String, bundleID: String) -> PathTarget {
    PathTarget(
        id: "editors.\(id)", group: "Editors", title: "\(title) cache", tier: .regenerates,
        paths: editorCacheFolders.map { "~/Library/Application Support/\(folder)/\($0)" },
        skipIfRunning: [bundleID]
    )
}

public enum BuiltinCatalog {
    public static let targets: [PathTarget] = [
        // macOS. Folders owned by other targets are excluded from these two at scan time (M2).
        PathTarget(id: "macos.caches", group: "macOS", title: "Other caches", tier: .regenerates,
                   flags: [.optIn], paths: ["~/Library/Caches"], contents: true),
        PathTarget(id: "macos.logs", group: "macOS", title: "Logs", tier: .regenerates,
                   paths: ["~/Library/Logs"], contents: true),

        // Xcode
        PathTarget(id: "xcode.deriveddata", group: "Xcode", title: "DerivedData", tier: .regenerates,
                   paths: ["~/Library/Developer/Xcode/DerivedData"], skipIfRunning: [xcode]),
        PathTarget(id: "xcode.archives", group: "Xcode", title: "Archives", tier: .dataLoss,
                   paths: ["~/Library/Developer/Xcode/Archives"]),
        PathTarget(id: "xcode.devicesupport", group: "Xcode", title: "Device support", tier: .redownload,
                   flags: [.heavy],
                   paths: ["~/Library/Developer/Xcode/iOS DeviceSupport",
                           "~/Library/Developer/Xcode/watchOS DeviceSupport",
                           "~/Library/Developer/Xcode/tvOS DeviceSupport"],
                   skipIfRunning: [xcode]),
        PathTarget(id: "xcode.caches", group: "Xcode", title: "Xcode and simulator caches", tier: .regenerates,
                   paths: ["~/Library/Caches/com.apple.dt.Xcode", "~/Library/Developer/CoreSimulator/Caches"],
                   skipIfRunning: [xcode]),
        PathTarget(id: "xcode.previews", group: "Xcode", title: "Previews and test devices", tier: .regenerates,
                   paths: ["~/Library/Developer/Xcode/UserData/Previews", "~/Library/Developer/XCTestDevices"],
                   skipIfRunning: [xcode]),
        PathTarget(id: "swiftpm", group: "Xcode", title: "Swift Package Manager cache", tier: .redownload,
                   paths: ["~/Library/Caches/org.swift.swiftpm"], skipIfRunning: [xcode]),
        PathTarget(id: "cocoapods", group: "Xcode", title: "CocoaPods cache", tier: .redownload,
                   paths: ["~/Library/Caches/CocoaPods"]),

        // Android
        PathTarget(id: "gradle", group: "Android", title: "Gradle caches", tier: .redownload,
                   paths: ["~/.gradle/caches", "~/.gradle/wrapper/dists", "~/.gradle/daemon"],
                   skipIfRunning: [androidStudio, "proc:Gradle=GradleDaemon"]),
        PathTarget(id: "android.systemimages", group: "Android", title: "Emulator system images", tier: .redownload,
                   flags: [.heavy], paths: ["~/Library/Android/sdk/system-images"],
                   skipIfRunning: [androidStudio, "proc:Android emulator=qemu-system"]),
        PathTarget(id: "android.avd", group: "Android", title: "Emulators (AVDs)", tier: .dataLoss,
                   flags: [.heavy], paths: ["~/.android/avd"],
                   skipIfRunning: [androidStudio, "proc:Android emulator=qemu-system"]),

        // Flutter
        PathTarget(id: "dart.pubcache", group: "Flutter", title: "Pub cache", tier: .redownload,
                   paths: ["~/.pub-cache"]),
        PathTarget(id: "dart.analysis", group: "Flutter", title: "Dart analysis cache", tier: .regenerates,
                   paths: ["~/.dartServer"], skipIfRunning: ["proc:Dart analysis server=dart.*language-server"]),

        // Node
        PathTarget(id: "yarn", group: "Node", title: "Yarn cache", tier: .redownload,
                   paths: ["~/Library/Caches/Yarn", "~/.yarn/berry/cache"]),
        PathTarget(id: "bun", group: "Node", title: "Bun cache", tier: .redownload,
                   paths: ["~/.bun/install/cache"]),
        PathTarget(id: "browsers", group: "Node", title: "Puppeteer and Playwright browsers", tier: .redownload,
                   paths: ["~/.cache/puppeteer", "~/Library/Caches/ms-playwright"]),
        PathTarget(id: "node-gyp", group: "Node", title: "node-gyp headers", tier: .redownload,
                   paths: ["~/Library/Caches/node-gyp"]),
        PathTarget(id: "electron", group: "Node", title: "Electron downloads", tier: .redownload,
                   paths: ["~/Library/Caches/electron", "~/Library/Caches/electron-builder"]),

        // Python
        PathTarget(id: "pip", group: "Python", title: "pip cache", tier: .redownload,
                   paths: ["~/Library/Caches/pip"]),
        PathTarget(id: "uv", group: "Python", title: "uv cache", tier: .redownload,
                   paths: ["~/.cache/uv"]),
        PathTarget(id: "poetry", group: "Python", title: "Poetry cache", tier: .redownload,
                   paths: ["~/Library/Caches/pypoetry"]),
        PathTarget(id: "conda.pkgs", group: "Python", title: "Conda package cache", tier: .redownload,
                   paths: ["~/miniconda3/pkgs", "~/anaconda3/pkgs", "~/miniforge3/pkgs"]),

        // PHP, Ruby, Java, .NET, Go, Homebrew
        PathTarget(id: "composer", group: "PHP", title: "Composer cache", tier: .redownload,
                   paths: ["~/Library/Caches/composer", "~/.composer/cache"]),
        PathTarget(id: "gem", group: "Ruby", title: "Gem specs cache", tier: .redownload,
                   paths: ["~/.gem/specs"]),
        PathTarget(id: "bundler", group: "Ruby", title: "Bundler cache", tier: .redownload,
                   paths: ["~/.bundle/cache"]),
        PathTarget(id: "maven", group: "Java", title: "Maven repository", tier: .redownload,
                   flags: [.optIn], paths: ["~/.m2/repository"]),
        PathTarget(id: "nuget", group: ".NET", title: "NuGet packages", tier: .redownload,
                   flags: [.optIn], paths: ["~/.nuget/packages"]),
        PathTarget(id: "go.buildcache", group: "Go", title: "Go build cache", tier: .regenerates,
                   paths: ["~/Library/Caches/go-build"]),
        PathTarget(id: "brew", group: "Homebrew", title: "Homebrew downloads", tier: .redownload,
                   paths: ["~/Library/Caches/Homebrew"]),

        // Editors. Bundle ids verified on the author's Mac: Devin uses com.exafunction.windsurf.
        editor("vscode", "VS Code", folder: "Code", bundleID: "com.microsoft.VSCode"), // unverified bundle id
        editor("cursor", "Cursor", folder: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92"), // unverified bundle id
        editor("windsurf", "Windsurf", folder: "Windsurf", bundleID: "com.exafunction.windsurf"),
        editor("devin", "Devin", folder: "Devin", bundleID: "com.exafunction.windsurf"),
        editor("zed", "Zed", folder: "Zed", bundleID: "dev.zed.Zed"), // unverified bundle id
        PathTarget(id: "editors.jetbrains", group: "Editors", title: "JetBrains caches and logs", tier: .regenerates,
                   paths: ["~/Library/Caches/JetBrains", "~/Library/Logs/JetBrains"],
                   skipIfRunning: ["proc:JetBrains IDE=/Contents/MacOS/(idea|webstorm|pycharm|goland|phpstorm|rider|clion|rubymine)"]),

        // Containers
        PathTarget(id: "orbstack", group: "Containers", title: "OrbStack logs and cache", tier: .regenerates,
                   paths: ["~/.orbstack/log", "~/Library/Caches/dev.kdrag0n.MacVirt"],
                   skipIfRunning: ["dev.kdrag0n.MacVirt"]), // unverified bundle id
    ]
}
