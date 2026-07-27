// PrototypeShotExporter — one-off CLI to render the WorkoutKeyboardPrototype
// SwiftUI view to PNG files under `design/prototype-shots/`. Not shipped in
// the app — this target only exists to produce the design-review screenshots
// referenced from north-star §11.
//
// Usage:
//   swift run --package-path Prototype PrototypeShotExporter <output-dir>
//
// The CLI renders 4 combinations (iPhone/iPad × light/dark) at the frame
// sizes defined in the Prototype's #Preview blocks.

import SwiftUI
import AppKit
import DesignKit
import Prototype

@MainActor
struct ExportSpec {
    let filename: String
    let width: CGFloat
    let height: CGFloat
    let isDark: Bool
}

@MainActor
func render(_ spec: ExportSpec, to outputDir: URL) throws {
    let theme = Theme(seed: .teal, neutral: .slate, isDark: spec.isDark)

    let view = WorkoutKeyboardPrototype()
        .environment(\.theme, theme)
        .environment(\.colorScheme, spec.isDark ? .dark : .light)
        .frame(width: spec.width, height: spec.height)
        .background(theme.neutrals.bg)

    let renderer = ImageRenderer(content: view)
    // Use 2x display scale for retina-quality shots.
    renderer.scale = 2.0

    guard let nsImage = renderer.nsImage else {
        throw NSError(domain: "PrototypeShotExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "ImageRenderer failed for \(spec.filename)"])
    }

    guard let tiffData = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "PrototypeShotExporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed for \(spec.filename)"])
    }

    let outputURL = outputDir.appendingPathComponent(spec.filename)
    try pngData.write(to: outputURL)
    FileHandle.standardOutput.write(Data("wrote \(outputURL.path)\n".utf8))
}

@MainActor
func run() throws {
    let args = CommandLine.arguments
    let outputPath: String = args.count >= 2 ? args[1] : "design/prototype-shots"

    let outputDir = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

    let specs: [ExportSpec] = [
        ExportSpec(filename: "keyboard-iphone-light.png", width: 393, height: 260, isDark: false),
        ExportSpec(filename: "keyboard-iphone-dark.png",  width: 393, height: 260, isDark: true),
        ExportSpec(filename: "keyboard-ipad-light.png",   width: 1024, height: 280, isDark: false),
        ExportSpec(filename: "keyboard-ipad-dark.png",    width: 1024, height: 280, isDark: true),
    ]

    for spec in specs {
        try render(spec, to: outputDir)
    }
}

// Top-level entry using DispatchQueue.main to bounce to MainActor since
// `main.swift` cannot use `@main` and the SwiftUI ImageRenderer needs main.
DispatchQueue.main.async {
    do {
        try MainActor.assumeIsolated { try run() }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        exit(1)
    }
}
RunLoop.main.run()
