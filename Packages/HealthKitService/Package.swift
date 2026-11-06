// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthKitService",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "HealthKitService", targets: ["HealthKitService"]),
    ],
    dependencies: [
        .package(path: "../VitalModels"),
    ],
    targets: [
        .target(
            name: "HealthKitService",
            dependencies: [
                .product(name: "VitalModels", package: "VitalModels"),
            ]
        ),
        .testTarget(
            name: "HealthKitServiceTests",
            dependencies: ["HealthKitService"]
        ),
    ]
)
