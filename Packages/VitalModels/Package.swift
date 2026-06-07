// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VitalModels",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "VitalModels", targets: ["VitalModels"]),
    ],
    targets: [
        .target(name: "VitalModels"),
        .testTarget(name: "VitalModelsTests", dependencies: ["VitalModels"]),
    ]
)
