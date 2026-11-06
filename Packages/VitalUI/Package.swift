// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VitalUI",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "VitalUI", targets: ["VitalUI"]),
    ],
    dependencies: [
        .package(path: "../VitalModels"),
    ],
    targets: [
        .target(
            name: "VitalUI",
            dependencies: [
                .product(name: "VitalModels", package: "VitalModels"),
            ]
        ),
        .testTarget(
            name: "VitalUITests",
            dependencies: ["VitalUI"]
        ),
    ]
)
