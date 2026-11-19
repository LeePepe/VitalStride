import AppKit
import DesignKit
import Prototype
import SwiftUI

@MainActor
private func view(for variant: Int) -> AnyView {
    let data = WorkoutLoadProgressionPreviewData()
    switch variant {
    case 1: return AnyView(WorkoutLoadProgressionV01View(data: data))
    case 2: return AnyView(WorkoutLoadProgressionV02View(data: data))
    case 3: return AnyView(WorkoutLoadProgressionV03View(data: data))
    case 4: return AnyView(WorkoutLoadProgressionV04View(data: data))
    case 5: return AnyView(WorkoutLoadProgressionV05View(data: data))
    case 6: return AnyView(WorkoutLoadProgressionV06View(data: data))
    case 7: return AnyView(WorkoutLoadProgressionV07View(data: data))
    case 8: return AnyView(WorkoutLoadProgressionV08View(data: data))
    case 9: return AnyView(WorkoutLoadProgressionV09View(data: data))
    default: return AnyView(WorkoutLoadProgressionV10View(data: data))
    }
}

@MainActor
private func render(variant: Int, isDark: Bool, to outputDir: URL) throws {
    let theme = Theme(seed: .teal, neutral: .slate, isDark: isDark)
    let content = view(for: variant)
        .environment(\.theme, theme)
        .environment(\.colorScheme, isDark ? .dark : .light)
        .frame(width: 393, height: 852, alignment: .top)
        .background(theme.canvas)
    let hostingView = NSHostingView(rootView: content)
    hostingView.frame = NSRect(x: 0, y: 0, width: 393, height: 852)
    hostingView.layoutSubtreeIfNeeded()
    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { throw ExportError.bitmap(variant) }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let outputBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 393, pixelsHigh: 852, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0) else { throw ExportError.bitmap(variant) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outputBitmap)
    bitmap.draw(in: NSRect(x: 0, y: 0, width: 393, height: 852), from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = outputBitmap.representation(using: .png, properties: [:]) else { throw ExportError.png(variant) }
    let path = outputDir.appendingPathComponent(String(format: "v%02d-%@.png", variant, isDark ? "dark" : "light"))
    try png.write(to: path)
    print(path.path)
}

private enum ExportError: Error { case bitmap(Int); case png(Int) }

@MainActor
private func run() throws {
    let path = CommandLine.arguments.dropFirst().first ?? ".build/workout-load-progression-shots"
    let outputDir = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    for variant in 1...10 { for isDark in [false, true] { try render(variant: variant, isDark: isDark, to: outputDir) } }
}

DispatchQueue.main.async {
    do { try MainActor.assumeIsolated { try run() }; exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}
RunLoop.main.run()
