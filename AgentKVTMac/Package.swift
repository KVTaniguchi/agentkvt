// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentKVTMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AgentKVTMac", targets: ["AgentKVTMac"]),
        .executable(name: "AgentKVTMacRunner", targets: ["AgentKVTMacRunner"])
    ],
    dependencies: [
        .package(path: "../ManagerCore")
    ],
    targets: [
        .target(
            name: "AgentKVTMac",
            dependencies: ["ManagerCore"]
        ),
        .executableTarget(
            name: "AgentKVTMacRunner",
            dependencies: ["AgentKVTMac", "ManagerCore"]
        ),
        .testTarget(
            name: "AgentKVTMacTests",
            dependencies: ["AgentKVTMac", "ManagerCore"]
        )
    ]
)
