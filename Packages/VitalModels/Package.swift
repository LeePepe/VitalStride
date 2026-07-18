// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VitalModels",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "VitalModels", targets: ["VitalModels"]),
    ],
    targets: [
        .plugin(
            name: "CompileXCStrings",
            capability: .buildTool()
        ),
        .target(
            name: "VitalModels",
            resources: [
                .process("Resources/Localizable.xcstrings"),
            ],
            plugins: [
                .plugin(name: "CompileXCStrings"),
            ]
        ),
        .testTarget(name: "VitalModelsTests", dependencies: ["VitalModels"]),
    ]
)
