// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArkavoC2PA",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "ArkavoC2PA",
            targets: ["ArkavoC2PA"]
        )
    ],
    targets: [
        .target(
            name: "ArkavoC2PA",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ArkavoC2PATests",
            dependencies: ["ArkavoC2PA"]
        )
    ]
)
