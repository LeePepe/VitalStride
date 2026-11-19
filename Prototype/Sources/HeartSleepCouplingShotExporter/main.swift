import AppKit
import DesignKit
import Prototype
import SwiftUI

@MainActor
private func view(for variant: Int) -> AnyView {
    let data = HeartSleepCouplingPreviewData()
    return switch variant {
    case 1: AnyView(HeartSleepCouplingV01View(data: data))
    case 2: AnyView(HeartSleepCouplingV02View(data: data))
    case 3: AnyView(HeartSleepCouplingV03View(data: data))
    case 4: AnyView(HeartSleepCouplingV04View(data: data))
    case 5: AnyView(HeartSleepCouplingV05View(data: data))
    case 6: AnyView(HeartSleepCouplingV06View(data: data))
    case 7: AnyView(HeartSleepCouplingV07View(data: data))
    case 8: AnyView(HeartSleepCouplingV08View(data: data))
    case 9: AnyView(HeartSleepCouplingV09View(data: data))
    default: AnyView(HeartSleepCouplingV10View(data: data))
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
    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw NSError(domain: "HeartSleepCouplingShotExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "v\(variant)"])
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
    guard let outputBitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 393,
        pixelsHigh: 852,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "HeartSleepCouplingShotExporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "v\(variant)"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: outputBitmap)
    bitmap.draw(in: NSRect(x: 0, y: 0, width: 393, height: 852), from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = outputBitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "HeartSleepCouplingShotExporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "v\(variant)"])
    }
    let filename = String(format: "v%02d-%@.png", variant, isDark ? "dark" : "light")
    try png.write(to: outputDir.appendingPathComponent(filename))
    print(outputDir.appendingPathComponent(filename).path)
}

@MainActor
private func run() throws {
    let path = CommandLine.arguments.dropFirst().first ?? ".build/heart-sleep-coupling-shots"
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
