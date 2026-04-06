// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AgentKVTMac",
    platforms: [
        .macOS(.v26)
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
            dependencies: ["ManagerCore"],
            linkerSettings: [
                .linkedFramework("CloudKit"),
                .linkedFramework("EventKit"),
                .linkedFramework("IOKit"),
            ]
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
