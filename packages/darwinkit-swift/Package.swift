// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DarwinKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "darwinkit", targets: ["DarwinKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jkrukowski/swift-embeddings", from: "0.0.26")
    ],
    targets: [
        .executableTarget(
            name: "DarwinKit",
            dependencies: [
                "DarwinKitCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/DarwinKit/Info.plist"
                ])
            ]
        ),
        .target(
            name: "DarwinKitCore",
            dependencies: [
                .product(name: "Embeddings", package: "swift-embeddings")
            ]
        ),
        .testTarget(
            name: "DarwinKitCoreTests",
            dependencies: ["DarwinKitCore"]
        )
    ]
)
