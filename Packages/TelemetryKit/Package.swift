// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TelemetryKit",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "TelemetryKit", targets: ["TelemetryKit"]),
        .library(name: "TelemetryDeckAdapter", targets: ["TelemetryDeckAdapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
    ],
    targets: [
        .target(name: "TelemetryKit"),
        .target(
            name: "TelemetryDeckAdapter",
            dependencies: [
                "TelemetryKit",
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ]
        ),
        .testTarget(
            name: "TelemetryKitTests",
            dependencies: ["TelemetryKit"]
        ),
        .testTarget(
            name: "TelemetryDeckAdapterTests",
            dependencies: ["TelemetryDeckAdapter"]
        ),
    ]
)
