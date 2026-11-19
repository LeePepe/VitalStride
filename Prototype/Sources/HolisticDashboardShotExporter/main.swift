import AppKit
import DesignKit
import Prototype
import SwiftUI

@MainActor
private struct ExportSpec {
    let filename: String
    let variant: Int
    let state: HolisticPreviewState
    let isDark: Bool
}

@MainActor
private func view(for spec: ExportSpec) -> AnyView {
    let data = HolisticDashboardPreviewData(state: spec.state)
    switch spec.variant {
    case 1: return AnyView(HolisticDashboardV01View(data: data))
    case 2: return AnyView(HolisticDashboardV02View(data: data))
    case 3: return AnyView(HolisticDashboardV03View(data: data))
    case 4: return AnyView(HolisticDashboardV04View(data: data))
    case 5: return AnyView(HolisticDashboardV05View(data: data))
    case 6: return AnyView(HolisticDashboardV06View(data: data))
    case 7: return AnyView(HolisticDashboardV07View(data: data))
    case 8: return AnyView(HolisticDashboardV08View(data: data))
    case 9: return AnyView(HolisticDashboardV09View(data: data))
    default: return AnyView(HolisticDashboardV10View(data: data))
    }
}

@MainActor
private func render(_ spec: ExportSpec, to outputDir: URL) throws {
    let theme = Theme(seed: .teal, neutral: .slate, isDark: spec.isDark)
    let content = view(for: spec)
        .environment(\.theme, theme)
        .environment(\.colorScheme, spec.isDark ? .dark : .light)
        .frame(width: 393, height: 852, alignment: .top)
        .background(theme.canvas)
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "HolisticDashboardShotExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: spec.filename])
    }
    let destination = outputDir.appendingPathComponent(spec.filename)
    try png.write(to: destination)
    print(destination.path)
}

@MainActor
private func run() throws {
    let outputPath = CommandLine.arguments.dropFirst().first ?? ".build/holistic-dashboard-shots"
    let outputDir = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    var specs: [ExportSpec] = []
    for variant in 1...10 {
        for isDark in [false, true] {
            specs.append(ExportSpec(filename: String(format: "v%02d-%@.png", variant, isDark ? "dark" : "light"), variant: variant, state: .populated, isDark: isDark))
        }
    }
    for state in HolisticPreviewState.allCases {
        for isDark in [false, true] {
            specs.append(ExportSpec(filename: "state-\(state.rawValue)-\(isDark ? "dark" : "light").png", variant: 1, state: state, isDark: isDark))
        }
    }
    for spec in specs { try render(spec, to: outputDir) }
}

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
