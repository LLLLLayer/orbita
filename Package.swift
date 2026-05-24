// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Orbita",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OrbitaCore", targets: ["OrbitaCore"]),
        .executable(name: "orbita", targets: ["OrbitaCLI"]),
        .executable(name: "OrbitaApp", targets: ["OrbitaApp"])
    ],
    targets: [
        .target(name: "OrbitaCore"),
        .executableTarget(
            name: "OrbitaCLI",
            dependencies: ["OrbitaCore"]
        ),
        .executableTarget(
            name: "OrbitaApp",
            dependencies: ["OrbitaCore"]
        ),
        .testTarget(
            name: "OrbitaCoreTests",
            dependencies: ["OrbitaCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "OrbitaCLITests",
            dependencies: ["OrbitaCLI"]
        )
    ]
)
