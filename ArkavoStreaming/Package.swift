// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArkavoStreaming",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0")
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
