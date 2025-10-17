// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArkavoAgentTest",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../ArkavoAgent")
    ],
    targets: [
        .executableTarget(
            name: "ArkavoAgentTest",
            dependencies: ["ArkavoAgent"]
        )
    ]
)
