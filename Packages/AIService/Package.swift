// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIService",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "AIService", targets: ["AIService"]),
    ],
    targets: [
        .target(name: "AIService"),
        .testTarget(
            name: "AIServiceTests",
            dependencies: ["AIService"]
        ),
    ]
)
