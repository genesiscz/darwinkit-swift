// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DarwinKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "darwinkit", targets: ["DarwinKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "DarwinKit",
            dependencies: [
                "DarwinKitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "DarwinKitCore"
        ),
        .testTarget(
            name: "DarwinKitCoreTests",
            dependencies: ["DarwinKitCore"]
        )
    ]
)
