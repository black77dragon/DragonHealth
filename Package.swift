// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DragonHealth",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DragonHealthApp", targets: ["DragonHealthApp"]),
        .library(name: "Core", targets: ["Core"]),
        .library(name: "CoreDB", targets: ["CoreDB"]),
        .library(name: "InfraLogging", targets: ["InfraLogging"]),
        .library(name: "InfraConfig", targets: ["InfraConfig"]),
        .library(name: "InfraFeatureFlags", targets: ["InfraFeatureFlags"])
    ],
    targets: [
        .executableTarget(
            name: "DragonHealthApp",
            dependencies: [
                "Core",
                "InfraLogging",
                "InfraConfig",
                "InfraFeatureFlags"
            ],
            path: "App"
        ),
        .target(
            name: "Core",
            path: "Core"
        ),
        .target(
            name: "CoreDB",
            dependencies: ["Core"],
            path: "Core/DB"
        ),
        .target(
            name: "InfraLogging",
            path: "Infra/Logging"
        ),
        .target(
            name: "InfraConfig",
            path: "Infra/Config"
        ),
        .target(
            name: "InfraFeatureFlags",
            path: "Infra/FeatureFlags"
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests/Unit"
        )
    ]
)
