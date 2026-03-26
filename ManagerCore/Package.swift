// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ManagerCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "ManagerCore", targets: ["ManagerCore"])
    ],
    targets: [
        .target(
            name: "ManagerCore",
            dependencies: []
        ),
        .testTarget(
            name: "ManagerCoreTests",
            dependencies: ["ManagerCore"]
        )
    ]
)
