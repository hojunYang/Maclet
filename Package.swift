// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Maclet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Maclet", targets: ["MacletApp"]),
        .library(name: "MacletCore", targets: ["MacletCore"])
    ],
    targets: [
        .target(
            name: "MacletCore"
        ),
        .executableTarget(
            name: "MacletApp",
            dependencies: ["MacletCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "MacletCoreTests",
            dependencies: ["MacletCore"]
        ),
        .testTarget(
            name: "MacletAppTests",
            dependencies: ["MacletApp"]
        )
    ]
)
