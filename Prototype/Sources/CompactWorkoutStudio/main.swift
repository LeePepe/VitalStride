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
                Toggle("Reduce transparency", isOn: $session.forceReduceTransparency)
                Toggle("Reduce motion", isOn: $session.forceReduceMotion)
                Divider()
                Button(studioText("screen.picker")) { session = CompactSession(picker: true) }
                Button(studioText("screen.workout")) { session = CompactSession() }
                Button(studioText("scenario.keyboard")) { session = CompactSession(); session.edit("weight") }
                Button(studioText("scenario.resting")) { session.core.restEnd = Date().addingTimeInterval(74) }
                Button(studioText("scenario.undo")) { session.deleteSelected() }
                Button(studioText("compact.browse")) { session.navigation.jump(to: "incline", order: session.core.workoutIDs) }
                Button(studioText("weight.splitDemo")) { session = weightExample("split-keyboard") }
                Button(studioText("weight.machineDemo")) { session = weightExample("machine-mode") }
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
func renderCompact(to path: String, chosenB: Bool = false, weights: Bool = false) throws {
    let output = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var count = 0
    func render(layout: CompactLayout, state: String, dark: Bool, large: Bool = false) throws {
        let session = weights ? weightExample(state) : CompactSession(picker: state.hasPrefix("picker"))
        let picker = CompactPickerModel()
        if !weights && (state.contains("keyboard") || state == "rpe") { session.edit("weight") }
        if state.contains("rest") { session.core.restEnd = Date().addingTimeInterval(74) }
        if state.contains("undo") { session.core.deleteSet(4) }
        if state == "more" { session.overlay = .more }
        if state == "rpe" { session.accessory = .rpe; session.setRPE(8) }
        if state == "picker-filter" { session.overlay = .filters }
        if state == "picker-empty" { picker.query = "zzzz"; picker.refresh() }
        if state.contains("empty") { session.setContentState(.empty) }
        if state.contains("loading") { session.setContentState(.loading) }
        if state.contains("error") { session.setContentState(.error) }
        session.forceReduceTransparency = state.contains("reduce-transparency") || state == "reduce-both"
        session.forceReduceMotion = state.contains("reduce-motion") || state == "reduce-both"
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
    if weights {
        for state in ["weight-mode", "split-mode", "split-keyboard", "split-saved", "machine-mode", "machine-default", "machine-applied", "machine-more", "keyboard-empty", "keyboard-loading", "keyboard-error", "weight-6char-max", "weight-invalid"] {
            for dark in [false, true] { try render(layout: .rail, state: state, dark: dark) }
        }
        for dark in [false, true] { try render(layout: .rail, state: "split-keyboard", dark: dark, large: true) }
    } else if chosenB {
        for state in ["normal", "keyboard", "rest", "undo", "keyboard-rest", "keyboard-undo", "rest-undo", "keyboard-rest-undo", "browse", "keyboard-browse", "more", "rpe", "picker", "picker-filter", "picker-empty", "workout-empty", "workout-loading", "workout-error", "picker-loading", "picker-error", "drawer-empty", "drawer-loading", "drawer-error", "snackbar-loading", "snackbar-error", "rail-only-browse", "rail-same-browse-edit", "rail-diff-browse-edit", "reduce-transparency", "reduce-motion", "reduce-both", "width-375", "long-bilingual", "weight-6char-valid", "weight-invalid-error"] {
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

@MainActor
func weightExample(_ state: String) -> CompactSession {
    let session = CompactSession()
    if state.hasPrefix("machine") {
        session.core.selectedIDs = ["machinepress"]; session.core.confirmSelection()
        _ = session.select(exercise: "machinepress")
        for _ in 0..<3 { session.core.addSet() }
        session.navigation.jump(to: "machinepress", order: session.core.workoutIDs)
        session.beginEquipmentDefault()
        for key in ["4", "5"] { session.pressEquipmentDefaultKey(key) }
        session.saveEquipmentDefault(); session.notice = nil
        if state == "machine-default" { session.beginEquipmentDefault() }
        else if state == "machine-applied" { session.applyEquipmentDefault() }
        else if state == "machine-more" { session.discardDraft(); session.overlay = .more }
        else { session.accessory = .weight }
    } else {
        session.edit("weight")
        if state.hasPrefix("split") {
            session.core.setEditorSplit(true)
            session.core.switchEditor(to: "weight"); session.core.pressEditorKey("2"); session.core.pressEditorKey("4")
            session.core.switchEditor(to: "weightRight"); session.core.pressEditorKey("2"); session.core.pressEditorKey("6")
        }
        if state == "split-saved" { session.save() }
        else { session.accessory = state == "split-keyboard" ? .digits : .weight }
    }
    return session
}

@MainActor
func verifyInteractive() throws {
    let session = CompactSession()
    let host = NSHostingView(rootView: CompactHost())
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 393, height: 852),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.contentView = host
    window.makeKeyAndOrderFront(nil)
    session.edit("weight")
    guard session.core.editorField == "weight" else { throw NSError(domain: "CompactVerify", code: 3) }
    session.core.switchEditor(to: "reps")
    guard session.core.editorField == "reps" else { throw NSError(domain: "CompactVerify", code: 4) }
    session.core.switchEditor(to: "weight")
    session.core.pressEditorKey("7")
    session.core.pressEditorKey("5")
    guard session.core.editorWeightText == "75" else { throw NSError(domain: "CompactVerify", code: 1) }
    session.setContentState(.loading)
    session.setContentState(.error)
    session.setContentState(.populated)
    session.save()
    guard session.core.editorField == nil, session.core.activeSets[2].weight == 75 else {
        throw NSError(domain: "CompactVerify", code: 2)
    }
    session.forceReduceTransparency = true
    session.forceReduceMotion = true
    host.rootView = CompactHost()
    host.layoutSubtreeIfNeeded()
    session.forceReduceTransparency = false
    session.forceReduceMotion = false
    window.orderOut(nil)
    FileHandle.standardOutput.write(Data("interactive verification passed: A1/A4/A6/A8/A9\n".utf8))
}

if CommandLine.arguments.contains("--render") || CommandLine.arguments.contains("--render-b") || CommandLine.arguments.contains("--render-weights") {
    let chosenB = CommandLine.arguments.contains("--render-b")
    let weights = CommandLine.arguments.contains("--render-weights")
    let path = CommandLine.arguments.dropFirst(2).first ?? (weights ? "Prototype/CompactEvidence/weight-shots" : (chosenB ? "Prototype/CompactEvidence/b-shots" : "Prototype/CompactEvidence/shots"))
    DispatchQueue.main.async {
        do { try MainActor.assumeIsolated { try renderCompact(to: path, chosenB: chosenB, weights: weights) }; exit(0) }
        catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
    }
    RunLoop.main.run()
} else if CommandLine.arguments.contains("--verify-interactive") {
    DispatchQueue.main.async {
        do { try MainActor.assumeIsolated { try verifyInteractive() }; exit(0) }
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
