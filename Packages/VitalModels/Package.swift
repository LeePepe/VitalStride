// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VitalModels",
    defaultLocalization: "zh-Hans",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
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
