// swift-tools-version: 6.0
import PackageDescription

// ============================================================================
//  DesignKit — the ONE design language for VitalStride (iOS / macOS / watchOS).
//
//  ONE seed color → the whole primary token set (makePrimaryPalette).
//  Neutral + semantic palettes are FIXED. Never fork the language or invent a
//  second palette. Same seed math as the design-system web port.
//
//  Currently an independent local package (like TelemetryKit). Register it in
//  project.yml + add to the app targets when wiring the UI to these tokens.
// ============================================================================

let package = Package(
    name: "DesignKit",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [
        .library(name: "DesignKit", targets: ["DesignKit"]),
    ],
    targets: [
        .target(
            name: "DesignKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DesignKitTests",
            dependencies: ["DesignKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
