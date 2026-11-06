// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlightKit",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
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
