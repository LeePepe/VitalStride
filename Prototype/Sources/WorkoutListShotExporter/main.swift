// WorkoutListShotExporter — one-off CLI to render the WorkoutListPrototype
// SwiftUI view to PNG files for the MY-1361 design gate. Not shipped in the
// app; only exists to produce the design-review screenshots referenced from
// docs/reports/018-workout-list-redesign-screenshots.md.
//
// Usage:
//   swift run --package-path Prototype WorkoutListShotExporter <output-dir>
//
// Renders the 5 required scenarios (loading / empty / failed / unauthorized /
// mixed-App+HK) in light + a light/dark accessibility variant for mixed, so
// the design gate has ≥4 light/dark × normal/Large captures with Apple Watch
// HK content.

import SwiftUI
import AppKit
import DesignKit
import Prototype

@MainActor
struct ListExportSpec {
    let filename: String
    let scenario: PrototypeListScenario
    let isDark: Bool
    let large: Bool
    let width: CGFloat
    let height: CGFloat
}

@MainActor
func renderList(_ spec: ListExportSpec, to outputDir: URL) throws {
    let theme = Theme(seed: .teal, neutral: .slate, isDark: spec.isDark)

    let base = WorkoutListPrototype(scenario: spec.scenario)
        .environment(\.theme, theme)
        .environment(\.colorScheme, spec.isDark ? .dark : .light)
        .frame(width: spec.width, height: spec.height)
        .background(theme.neutrals.bg)

    // ImageRenderer's generic constraints force us to apply the modifier at
    // one type — branch on `large` and pick the concrete typed view.
    let view: AnyView = spec.large
        ? AnyView(base.dynamicTypeSize(.accessibility1))
        : AnyView(base.dynamicTypeSize(.large))

    let renderer = ImageRenderer(content: view)
    renderer.scale = 2.0

    guard let nsImage = renderer.nsImage else {
        throw NSError(
            domain: "WorkoutListShotExporter",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "ImageRenderer failed for \(spec.filename)"]
        )
    }

    guard let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "WorkoutListShotExporter",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "PNG encode failed for \(spec.filename)"]
        )
    }

    let outputURL = outputDir.appendingPathComponent(spec.filename)
    try pngData.write(to: outputURL)
    FileHandle.standardOutput.write(Data("wrote \(outputURL.path)\n".utf8))
}

@MainActor
func runList() throws {
    let args = CommandLine.arguments
    let outputPath: String = args.count >= 2
        ? args[1]
        : "docs/reports/018-workout-list-redesign-screenshots"

    let outputDir = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    // iPhone 16 preview frame width; height chosen tall enough for a mixed
    // list without clipping.
    let W: CGFloat = 393
    let H: CGFloat = 700

    let specs: [ListExportSpec] = [
        // Load-state banners (light, normal type)
        ListExportSpec(
            filename: "05-banner-loading-light-large.png",
            scenario: .loading, isDark: false, large: false, width: W, height: 260
        ),
        ListExportSpec(
            filename: "06-banner-failed-light-large.png",
            scenario: .failed, isDark: false, large: false, width: W, height: 260
        ),
        ListExportSpec(
            filename: "07-banner-unauthorized-light-large.png",
            scenario: .unauthorized, isDark: false, large: false, width: W, height: 260
        ),
        ListExportSpec(
            filename: "08-banner-unauthorized-dark-accessibility.png",
            scenario: .unauthorized, isDark: true, large: true, width: W, height: 340
        ),
        // Empty state
        ListExportSpec(
            filename: "09-empty-light-large.png",
            scenario: .empty, isDark: false, large: false, width: W, height: H
        ),
        // Mixed App + HK (Apple Watch fixture) — 4 required captures
        ListExportSpec(
            filename: "01-list-mixed-light-large.png",
            scenario: .mixed, isDark: false, large: false, width: W, height: H
        ),
        ListExportSpec(
            filename: "02-list-mixed-dark-large.png",
            scenario: .mixed, isDark: true, large: false, width: W, height: H
        ),
        ListExportSpec(
            filename: "03-list-mixed-light-accessibility.png",
            scenario: .mixed, isDark: false, large: true, width: W, height: 900
        ),
        ListExportSpec(
            filename: "04-list-mixed-dark-accessibility.png",
            scenario: .mixed, isDark: true, large: true, width: W, height: 900
        ),
    ]

    for spec in specs {
        try renderList(spec, to: outputDir)
    }
}

DispatchQueue.main.async {
    do {
        try MainActor.assumeIsolated { try runList() }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}
RunLoop.main.run()
