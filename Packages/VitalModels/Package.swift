// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VitalModels",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "VitalModels", targets: ["VitalModels"]),
    ],
    targets: [
        .target(
            name: "VitalModels",
            exclude: ["Resources/Localizable.xcstrings"],
            resources: [
                .process("Resources/zh-Hans.lproj"),
            ]
        ),
        .testTarget(name: "VitalModelsTests", dependencies: ["VitalModels"]),
    ]
)
