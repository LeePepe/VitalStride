// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VitalUI",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
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
    ]
)
