// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArkavoStreaming",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "ArkavoStreaming",
            targets: ["ArkavoStreaming"]
        )
    ],
    targets: [
        .target(
            name: "ArkavoStreaming",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ArkavoStreamingTests",
            dependencies: ["ArkavoStreaming"]
        )
    ]
)
