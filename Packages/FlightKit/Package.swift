// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlightKit",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "FlightKit", targets: ["FlightKit"]),
    ],
    targets: [
        .target(
            name: "FlightKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "FlightKitTests",
            dependencies: ["FlightKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
