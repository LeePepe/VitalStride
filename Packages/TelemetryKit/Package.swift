// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TelemetryKit",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "TelemetryKit", targets: ["TelemetryKit"]),
    ],
    targets: [
        .target(name: "TelemetryKit"),
        .testTarget(
            name: "TelemetryKitTests",
            dependencies: ["TelemetryKit"]
        ),
    ]
)
