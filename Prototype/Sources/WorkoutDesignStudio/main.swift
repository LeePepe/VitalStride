import AppKit
import DesignKit
import Prototype
import SwiftUI

@MainActor
struct StudioHost: View {
    @State private var style = StudioStyle.tide
    @State private var layout = StudioLayout.flow
    @State private var dark = false
    @State private var session = StudioSession()
    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 24) {
                Text("VitalStride").font(.largeTitle.bold())
                Text(studioText("studio.title")).font(.title2)
                Text(studioText("studio.description")).font(.body).foregroundStyle(.secondary)
                Picker(studioText("studio.style"), selection: $style) {
                    ForEach(StudioStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker(studioText("studio.layout"), selection: $layout) {
                    ForEach(StudioLayout.allCases) { Text($0.title).tag($0) }
                }
                Toggle(studioText("studio.dark"), isOn: $dark)
                ForEach(StudioScreen.allCases) { screen in
                    Button(screen.title) { session.screen = screen; session.isFinished = false }
                }
                Divider()
                ForEach([StudioScenario.normal, .noResults, .emptyLibrary, .resting, .undo, .keyboard, .finished], id: \.rawValue) { scenario in
                    Button(studioText("scenario.\(scenario.rawValue)")) {
                        session = StudioSession(screen: [.noResults, .emptyLibrary].contains(scenario) ? .picker : .workout, scenario: scenario)
                    }
                }
                Spacer()
                Text(studioText("studio.demoNote")).font(.caption).foregroundStyle(.secondary)
            }.frame(width: 260).padding(.vertical, 20)
            WorkoutStudioView(session: session, style: style, layout: layout)
                .environment(\.theme, style.theme(dark: dark))
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: 393, height: 852)
                .clipShape(RoundedRectangle(cornerRadius: 28))
        }.padding(32).frame(width: 749, height: 916)
    }
}

@MainActor
final class StudioDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 749, height: 916),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "VitalStride · Workout Design Studio"
        window.contentView = NSHostingView(rootView: StudioHost())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@MainActor
func renderStudio(to path: String) throws {
    let output = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var total = 0
    func render(style: StudioStyle, layout: StudioLayout, screen: StudioScreen, dark: Bool,
                scenario: StudioScenario = .normal, width: CGFloat = 393, large: Bool = false) throws {
        let session = StudioSession(screen: screen, scenario: scenario)
        // Freeze date-based rest relative to the render, no fake production data.
        let view = WorkoutStudioView(session: session, style: style, layout: layout, snapshot: true)
            .environment(\.theme, style.theme(dark: dark))
            .environment(\.colorScheme, dark ? .dark : .light)
            .dynamicTypeSize(large ? .accessibility1 : .large)
            .frame(width: width, height: 852)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let picture = renderer.nsImage, let tiff = picture.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "StudioRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Render failed"])
        }
        let suffix = scenario == .normal && !large && width == 393 ? "" : "-\(scenario.rawValue)\(large ? "-large" : "")\(width == 375 ? "-narrow" : "")"
        let name = "\(style.rawValue)-\(layout.rawValue)-\(screen.rawValue)-\(dark ? "dark" : "light")\(suffix).png"
        try png.write(to: output.appendingPathComponent(name))
        total += 1
    }
    for style in StudioStyle.allCases {
        for layout in StudioLayout.allCases {
            for screen in StudioScreen.allCases {
                for dark in [false, true] { try render(style: style, layout: layout, screen: screen, dark: dark) }
            }
        }
    }
    for scenario in [StudioScenario.noResults, .emptyLibrary, .resting, .undo, .keyboard, .finished] {
        let screen: StudioScreen = [.noResults, .emptyLibrary].contains(scenario) ? .picker : .workout
        for dark in [false, true] {
            try render(style: .tide, layout: .flow, screen: screen, dark: dark, scenario: scenario)
        }
    }
    for layout in StudioLayout.allCases {
        for screen in StudioScreen.allCases {
            try render(style: .tide, layout: layout, screen: screen, dark: false, width: 375, large: true)
        }
    }
    FileHandle.standardOutput.write(Data("Rendered \(total) native SwiftUI PNGs to \(path)\n".utf8))
}

let arguments = CommandLine.arguments
if arguments.contains("--render") {
    let path = arguments.dropFirst(2).first ?? "Prototype/RedesignEvidence/shots"
    DispatchQueue.main.async {
        do {
            try MainActor.assumeIsolated { try renderStudio(to: path) }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1)
        }
    }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = StudioDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
