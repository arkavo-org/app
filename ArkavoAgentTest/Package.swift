// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArkavoAgentTest",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "../ArkavoKit")
    ],
    targets: [
        .executableTarget(
            name: "ArkavoAgentTest",
            dependencies: [
                .product(name: "ArkavoKit", package: "ArkavoKit")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
