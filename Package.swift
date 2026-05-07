// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Flow",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", .upToNextMinor(from: "0.9.0"))
    ],
    targets: [
        .executableTarget(
            name: "Flow",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        )
    ]
)
