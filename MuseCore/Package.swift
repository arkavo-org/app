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
        .package(url: "https://github.com/arkavo-org/VRMMetalKit", exact: "0.9.2")
    ],
    targets: [
        .target(
            name: "MuseCore",
            dependencies: ["VRMMetalKit"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
