// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WonderShow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "WonderShow",
            targets: ["WonderShow"]
        ),
        .executable(
            name: "WonderShowApp",
            targets: ["WonderShowApp"]
        ),
        .executable(
            name: "screen-capture-diagnostic",
            targets: ["ScreenCaptureDiagnostic"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "WonderShow"
        ),
        .executableTarget(
            name: "WonderShowApp",
            dependencies: ["WonderShow"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ScreenCaptureDiagnostic",
            dependencies: ["WonderShow"]
        ),
        .testTarget(
            name: "WonderShowTests",
            dependencies: ["WonderShow"]
        ),
        .testTarget(
            name: "WonderShowAppTests",
            dependencies: ["WonderShowApp"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
