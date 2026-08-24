// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MSLSettings",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MSLControlCore", targets: ["MSLControlCore"]),
        .executable(name: "MSLSettingsApp", targets: ["MSLSettingsApp"]),
    ],
    targets: [
        .target(name: "MSLControlCore"),
        .executableTarget(
            name: "MSLSettingsApp",
            dependencies: ["MSLControlCore"]
        ),
        .testTarget(
            name: "MSLControlCoreTests",
            dependencies: ["MSLControlCore"]
        ),
    ]
)
