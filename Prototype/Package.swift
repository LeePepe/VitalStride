// swift-tools-version: 6.0
import PackageDescription

// ============================================================================
//  Prototype — isolated SwiftUI visual prototype target for design iteration.
//
//  Depends only on the local DesignKit package (tokens + Theme). Deliberately
//  isolated from production modules (VitalModels / SwiftData / VitalStride
//  app target). Visual-only; not embedded in any app target.
//
//  Preview-driven design: iterate visuals here, export screenshots for design
//  review, then port the frozen design over to the production widget in a
//  separate stage. See specs/017-workout-keyboard-redesign.
// ============================================================================

let package = Package(
    name: "Prototype",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Prototype", targets: ["Prototype"]),
        .executable(name: "PrototypeShotExporter", targets: ["PrototypeShotExporter"]),
        .executable(name: "WorkoutListShotExporter", targets: ["WorkoutListShotExporter"]),
    ],
    dependencies: [
        .package(path: "../Packages/DesignKit"),
    ],
    targets: [
        .target(
            name: "Prototype",
            dependencies: [
                .product(name: "DesignKit", package: "DesignKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "PrototypeShotExporter",
            dependencies: [
                "Prototype",
                .product(name: "DesignKit", package: "DesignKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "WorkoutListShotExporter",
            dependencies: [
                "Prototype",
                .product(name: "DesignKit", package: "DesignKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
