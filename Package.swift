// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "V2rayNSentinel",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SentinelCore"),
        .target(name: "AppLogic", dependencies: ["SentinelCore"]),
        .executableTarget(
            name: "V2rayNSentinel",
            dependencies: ["SentinelCore", "AppLogic"]
        ),
        .testTarget(name: "SentinelCoreTests", dependencies: ["SentinelCore"]),
        .testTarget(name: "AppLogicTests", dependencies: ["AppLogic"]),
    ]
)
