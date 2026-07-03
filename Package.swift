// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "V2rayNSentinel",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SentinelCore"),
        .executableTarget(
            name: "V2rayNSentinel",
            dependencies: ["SentinelCore"]
        ),
        .testTarget(
            name: "SentinelCoreTests",
            dependencies: ["SentinelCore"]
        ),
    ]
)
