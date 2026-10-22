// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "phew",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PhewCore", targets: ["PhewCore"]),
        .executable(name: "phew", targets: ["phew"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "PhewCore"),
        .executableTarget(
            name: "phew",
            dependencies: [
                "PhewCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "PhewApp", dependencies: ["PhewCore"]),
        .testTarget(name: "PhewCoreTests", dependencies: ["PhewCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "PhewAppTests", dependencies: ["PhewApp", "PhewCore"]),
        .testTarget(name: "PhewCLITests", dependencies: [
            "phew", "PhewCore", .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
    ]
)
