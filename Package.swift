// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DragonHealth",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "CoreDB", targets: ["CoreDB"]),
        .library(name: "InfraLogging", targets: ["InfraLogging"]),
        .library(name: "InfraConfig", targets: ["InfraConfig"]),
        .library(name: "InfraFeatureFlags", targets: ["InfraFeatureFlags"])
    ],
    targets: [
        .target(
            name: "Core",
            path: "Core",
            exclude: ["DB", "README.md"]
        ),
        .target(
            name: "CoreDB",
            dependencies: ["Core"],
            path: "Core/DB",
            exclude: ["README.md"]
        ),
        .target(
            name: "InfraLogging",
            path: "Infra/Logging",
            exclude: ["README.md"]
        ),
        .target(
            name: "InfraConfig",
            path: "Infra/Config",
            exclude: ["README.md"]
        ),
        .target(
            name: "InfraFeatureFlags",
            path: "Infra/FeatureFlags",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core", "CoreDB"],
            path: "Tests/Unit",
            exclude: ["README.md"]
        )
    ]
)
