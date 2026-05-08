// swift-tools-version: 6.3
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
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.3"),
        .package(url: "https://github.com/arkavo-ai/mlx-swift-lm", branch: "feature/gemma4-text"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.2.1"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "MuseCore",
            dependencies: [
                "VRMMetalKit",
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "MuseCoreTests",
            dependencies: ["MuseCore"]
        )
    ]
)
