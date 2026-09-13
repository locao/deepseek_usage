// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekUsage",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(name: "DeepSeekUsageCore"),
        .executableTarget(
            name: "DeepSeekUsage",
            dependencies: ["DeepSeekUsageCore"]
        ),
        .testTarget(
            name: "DeepSeekUsageCoreTests",
            dependencies: ["DeepSeekUsageCore"]
        ),
    ]
)
