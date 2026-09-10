// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolyPals",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PolyPals", targets: ["PolyPals"]),
        .library(name: "PolyPalsPluginKit", targets: ["PolyPalsPluginKit"]),
        .executable(name: "validate-pack", targets: ["validate-pack"])
    ],
    targets: [
        .executableTarget(
            name: "PolyPals",
            dependencies: ["PolyPalsPluginKit"],
            resources: [.process("Resources")]
        ),
        .target(name: "PolyPalsPluginKit"),
        .executableTarget(name: "validate-pack", dependencies: ["PolyPalsPluginKit"], path: "Sources/ValidatePack"),
        .testTarget(
            name: "PolyPalsTests",
            dependencies: ["PolyPals", "PolyPalsPluginKit"]
        ),
        .testTarget(
            name: "PolyPalsUITests",
            dependencies: ["PolyPals"]
        )
    ]
)
