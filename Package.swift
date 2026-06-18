// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PresenterDirector",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PresenterDirector",
            targets: ["PresenterDirector"]
        ),
        .executable(
            name: "PresenterDirectorApp",
            targets: ["PresenterDirectorApp"]
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
            name: "PresenterDirector"
        ),
        .executableTarget(
            name: "PresenterDirectorApp",
            dependencies: ["PresenterDirector"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ScreenCaptureDiagnostic",
            dependencies: ["PresenterDirector"]
        ),
        .testTarget(
            name: "PresenterDirectorTests",
            dependencies: ["PresenterDirector"]
        ),
        .testTarget(
            name: "PresenterDirectorAppTests",
            dependencies: ["PresenterDirectorApp"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
