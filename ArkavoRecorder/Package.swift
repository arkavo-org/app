// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArkavoRecorder",
    platforms: [
        .macOS(.v26),
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "ArkavoRecorder",
            targets: ["ArkavoRecorder"]
        )
    ],
    dependencies: [
        .package(path: "../ArkavoStreaming")
    ],
    targets: [
        .target(
            name: "ArkavoRecorder",
            dependencies: [
                .product(name: "ArkavoStreaming", package: "ArkavoStreaming")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ArkavoRecorderTests",
            dependencies: ["ArkavoRecorder"]
        )
    ]
)
