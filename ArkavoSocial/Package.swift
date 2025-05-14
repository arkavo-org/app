// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ArkavoSocial",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .watchOS(.v11),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ArkavoSocial",
            targets: ["ArkavoSocial"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/arkavo-org/OpenTDFKit", revision: "a1cf46bb12a7a48ef01a42edeb5583098483b4cd"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ArkavoSocial",
            dependencies: ["OpenTDFKit"]
        ),
        .testTarget(
            name: "ArkavoSocialTests",
            dependencies: ["ArkavoSocial"]
        ),
    ]
)
