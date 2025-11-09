// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArkavoRecorderShared",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "ArkavoRecorderShared",
            targets: ["ArkavoRecorderShared"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ArkavoRecorderShared",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ArkavoRecorderSharedTests",
            dependencies: ["ArkavoRecorderShared"]
        )
    ]
)
