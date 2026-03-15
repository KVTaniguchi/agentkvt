// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ManagerCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
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
