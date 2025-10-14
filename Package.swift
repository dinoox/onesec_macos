// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "OnesecCore",
    platforms: [
        .macOS(.v10_15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .executable(
            name: "OnesecCore",
            targets: ["OnesecCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/daltoniam/Starscream.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", .upToNextMajor(from: "2.0.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "OnesecCore",
            dependencies: [
                .product(name: "Starscream", package: "Starscream"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftyBeaver", package: "SwiftyBeaver"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "OnesecCoreTests",
            dependencies: ["OnesecCore"]
        ),
    ]
)
