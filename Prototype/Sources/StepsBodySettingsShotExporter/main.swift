import AppKit
import DesignKit
import Prototype
import SwiftUI

@MainActor
private func view(for variant: Int) -> AnyView {
    let data = StepsBodySettingsPreviewData()
    switch variant {
    case 1: return AnyView(StepsBodySettingsV01View(data: data))
    case 2: return AnyView(StepsBodySettingsV02View(data: data))
    case 3: return AnyView(StepsBodySettingsV03View(data: data))
    case 4: return AnyView(StepsBodySettingsV04View(data: data))
    case 5: return AnyView(StepsBodySettingsV05View(data: data))
    case 6: return AnyView(StepsBodySettingsV06View(data: data))
    case 7: return AnyView(StepsBodySettingsV07View(data: data))
    case 8: return AnyView(StepsBodySettingsV08View(data: data))
    case 9: return AnyView(StepsBodySettingsV09View(data: data))
    default: return AnyView(StepsBodySettingsV10View(data: data))
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
    try png.write(to: outputDir.appendingPathComponent(String(format: "v%02d-%@.png", variant, isDark ? "dark" : "light")))
}

private enum ExportError: Error { case bitmap(Int); case png(Int) }

@MainActor
private func run() throws {
    let path = CommandLine.arguments.dropFirst().first ?? ".build/steps-body-settings-shots"
    let outputDir = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    for variant in 1...10 {
        for isDark in [false, true] { try render(variant: variant, isDark: isDark, to: outputDir) }
    }
}

DispatchQueue.main.async {
    do { try MainActor.assumeIsolated { try run() }; exit(0) }
    catch { FileHandle.standardError.write(Data("error: \(error)\n".utf8)); exit(1) }
}
RunLoop.main.run()
