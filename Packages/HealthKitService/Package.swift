// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HealthKitService",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
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
