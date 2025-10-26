// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ArkavoAgent",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "ArkavoAgent",
            targets: ["ArkavoAgent"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ArkavoAgent",
            dependencies: []
        ),
        .testTarget(
            name: "ArkavoAgentTests",
            dependencies: ["ArkavoAgent"]
        ),
    ]
)
