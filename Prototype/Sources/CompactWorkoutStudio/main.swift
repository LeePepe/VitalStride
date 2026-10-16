import AppKit
import DesignKit
import Prototype
import SwiftUI

@MainActor
struct CompactHost: View {
    @State private var layout = CompactLayout.rail
    @State private var dark = false
    @State private var session = CompactSession()
    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("VitalStride B").font(.title.bold())
                ForEach(CompactLayout.allCases) { item in Button(item.title) { layout = item } }
                Toggle(studioText("studio.dark"), isOn: $dark)
                Divider()
                Button(studioText("screen.picker")) { session = CompactSession(picker: true) }
                Button(studioText("screen.workout")) { session = CompactSession() }
                Button(studioText("scenario.keyboard")) { session = CompactSession(); session.edit("weight") }
                Button(studioText("scenario.resting")) { session.core.restEnd = Date().addingTimeInterval(74) }
                Button(studioText("scenario.undo")) { session.deleteSelected() }
                Button(studioText("compact.browse")) { session.navigation.jump(to: "incline", order: session.core.workoutIDs) }
                Text(studioText("studio.demoNote")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.frame(width: 240)
            CompactStudioView(session: session, layout: layout)
                .environment(\.theme, Theme(seed: .blue, neutral: .slate, isDark: dark))
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: 393, height: 852).clipShape(RoundedRectangle(cornerRadius: 16))
        }.padding(24).frame(width: 705, height: 900)
    }
}

@MainActor
final class CompactDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 705, height: 900), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "VitalStride B"
        window.contentView = NSHostingView(rootView: CompactHost())
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
func renderCompact(to path: String, chosenB: Bool = false) throws {
    let output = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var count = 0
    func render(layout: CompactLayout, state: String, dark: Bool, large: Bool = false) throws {
        let session = CompactSession(picker: state.hasPrefix("picker"))
        let picker = CompactPickerModel()
        if state.contains("keyboard") || state == "rpe" { session.edit("weight") }
        if state.contains("rest") { session.core.restEnd = Date().addingTimeInterval(74) }
        if state.contains("undo") { session.core.deleteSet(4) }
        if state == "more" { session.overlay = .more }
        if state == "rpe" { session.accessory = .rpe; session.setRPE(8) }
        if state == "picker-filter" { session.overlay = .filters }
        if state == "picker-empty" { picker.query = "zzzz"; picker.refresh() }
        if state == "browse" || state == "keyboard-browse" {
            session.navigation.jump(to: "incline", order: session.core.workoutIDs)
        }
        let width: CGFloat = large ? 375 : 393
        let view = CompactStudioView(session: session, layout: layout, snapshot: true, picker: picker)
            .environment(\.theme, Theme(seed: .blue, neutral: .slate, isDark: dark))
            .environment(\.colorScheme, dark ? .dark : .light).dynamicTypeSize(large ? .accessibility1 : .large)
            .frame(width: width, height: 852)
        let renderer = ImageRenderer(content: view); renderer.scale = 2
        guard let image = renderer.nsImage, let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "CompactRenderer", code: 1)
        }
        try png.write(to: output.appendingPathComponent("\(layout.rawValue)-\(state)-\(dark ? "dark" : "light")\(large ? "-large-narrow" : "").png"))
        count += 1
    }
    if chosenB {
        for state in ["normal", "keyboard", "rest", "undo", "keyboard-rest", "keyboard-undo", "rest-undo", "keyboard-rest-undo", "browse", "keyboard-browse", "more", "rpe", "picker", "picker-filter", "picker-empty"] {
            for dark in [false, true] { try render(layout: .rail, state: state, dark: dark) }
        }
        for dark in [false, true] { try render(layout: .rail, state: "keyboard-rest", dark: dark, large: true) }
    } else {
        for layout in CompactLayout.allCases {
            for state in ["normal", "keyboard", "rest", "undo", "keyboard-rest", "keyboard-undo"] {
                for dark in [false, true] { try render(layout: layout, state: state, dark: dark) }
            }
            for dark in [false, true] { try render(layout: layout, state: "keyboard", dark: dark, large: true) }
        }
        for state in ["more", "rpe", "picker", "picker-filter", "picker-empty"] {
            for dark in [false, true] { try render(layout: .table, state: state, dark: dark) }
        }
    }
    FileHandle.standardOutput.write(Data("Rendered \(count) compact SwiftUI screens\n".utf8))
}

if CommandLine.arguments.contains("--render") || CommandLine.arguments.contains("--render-b") {
    let chosenB = CommandLine.arguments.contains("--render-b")
    let path = CommandLine.arguments.dropFirst(2).first ?? (chosenB ? "Prototype/CompactEvidence/b-shots" : "Prototype/CompactEvidence/shots")
    DispatchQueue.main.async {
        do { try MainActor.assumeIsolated { try renderCompact(to: path, chosenB: chosenB) }; exit(0) }
        catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
    }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared, delegate = CompactDelegate()
        app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
