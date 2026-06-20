// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "WonderShowCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WonderShowCore",
            targets: ["WonderShowCore"]
        )
    ],
    targets: [
        .target(
            name: "WonderShowCore"
        ),
        .testTarget(
            name: "WonderShowCoreTests",
            dependencies: ["WonderShowCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)

