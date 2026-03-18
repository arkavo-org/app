// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MuseCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "MuseCore",
            targets: ["MuseCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/arkavo-org/VRMMetalKit", exact: "0.9.2"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples", from: "2.29.1"),
    ],
    targets: [
        .target(
            name: "MuseCore",
            dependencies: [
                "VRMMetalKit",
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
