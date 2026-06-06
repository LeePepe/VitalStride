// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIService",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
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
