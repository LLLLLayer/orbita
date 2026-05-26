// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Orbita",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "OrbitaCore", targets: ["OrbitaCore"]),
        .executable(name: "orbita", targets: ["OrbitaCLI"]),
        .executable(name: "OrbitaApp", targets: ["OrbitaApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2"),
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.3.1")
    ],
    targets: [
        .target(name: "OrbitaCore"),
        .executableTarget(
            name: "OrbitaCLI",
            dependencies: ["OrbitaCore"]
        ),
        .executableTarget(
            name: "OrbitaApp",
            dependencies: [
                "OrbitaCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Textual", package: "textual")
            ],
            resources: [
                .process("Resources")
            ]
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
