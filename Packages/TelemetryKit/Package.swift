// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TelemetryKit",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "TelemetryKit", targets: ["TelemetryKit"]),
        .library(name: "AptabaseAdapter", targets: ["AptabaseAdapter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/aptabase/aptabase-swift", from: "0.3.11"),
    ],
    targets: [
        .target(name: "TelemetryKit"),
        .target(
            name: "AptabaseAdapter",
            dependencies: [
                "TelemetryKit",
                .product(name: "Aptabase", package: "aptabase-swift"),
            ]
        ),
        .testTarget(
            name: "TelemetryKitTests",
            dependencies: ["TelemetryKit"]
        ),
        .testTarget(
            name: "AptabaseAdapterTests",
            dependencies: ["AptabaseAdapter"]
        ),
    ]
)
