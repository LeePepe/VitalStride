// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TelemetryKit",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
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
