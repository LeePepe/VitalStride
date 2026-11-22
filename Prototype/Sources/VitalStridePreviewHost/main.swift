import AppKit
import DesignKit
import ImageIO
import Prototype
import SwiftUI
import UniformTypeIdentifiers

@MainActor
private enum VitalStridePreviewHostRunner {
    static func run() {
        let args = Array(CommandLine.arguments.dropFirst())
        var snapshotPath: String?
        var snapshotAllDir: String?
        var archiveAndReset = false
        var archiveRound: Int?
        var initialPage: VitalStridePreviewPageTab = .page1HolisticDashboard

        var idx = 0
        while idx < args.count {
            switch args[idx] {
            case "--snapshot":
                if idx + 1 < args.count {
                    snapshotPath = args[idx + 1]
                    idx += 1
                }
            case "--snapshot-all":
                if idx + 1 < args.count && !args[idx + 1].hasPrefix("--") {
                    snapshotAllDir = args[idx + 1]
                    idx += 1
                } else {
                    snapshotAllDir = "\(VitalStridePreviewPageTab.handoffRootDirectory)/vs-preview-host-app/snapshots"
                }
            case "--archive-and-reset":
                archiveAndReset = true
            case "--round":
                if idx + 1 < args.count, let round = Int(args[idx + 1]) {
                    archiveRound = round
                    idx += 1
                }
            case "--goal", "--page":
                if idx + 1 < args.count {
                    initialPage = parsePageTab(args[idx + 1])
                    idx += 1
                }
            default:
                break
            }
            idx += 1
        }

        if archiveAndReset {
            do {
                try archiveAndResetAllPageReceipts(explicitRound: archiveRound)
                exit(0)
            } catch {
                fputs("Failed to archive and reset preview receipts: \(error)\n", stderr)
                exit(1)
            }
        }

        if let snapshotAllDir {
            do {
                try renderAllPageSnapshots(into: URL(fileURLWithPath: snapshotAllDir, isDirectory: true))
                exit(0)
            } catch {
                fputs("Failed to export all page snapshots: \(error)\n", stderr)
                exit(1)
            }
        }

        if let snapshotPath {
            do {
                try renderBoardSnapshot(page: initialPage, to: URL(fileURLWithPath: snapshotPath))
                exit(0)
            } catch {
                fputs("Failed to export snapshot: \(error)\n", stderr)
                exit(1)
            }
        }

        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = VitalStridePreviewHostAppDelegate(initialPage: initialPage)
        app.delegate = delegate
        app.run()
    }

    static func parsePageTab(_ raw: String) -> VitalStridePreviewPageTab {
        let token = raw.lowercased()
        if token == "2" || token == "l2" || token.contains("coupling") || token.contains("heart") || token.contains("sleep") || token.contains("w2-3") {
            return .page2HeartSleepCoupling
        } else if token == "3" || token == "l3" || token.contains("readiness") || token.contains("periodization") || token.contains("load") || token.contains("workout") || token.contains("w2-4") {
            return .page3WorkoutLoadProgression
        } else if token == "4" || token == "l4" || token.contains("north-star") || token.contains("directive") || token.contains("step") || token.contains("body") || token.contains("w2-5") {
            return .page4StepsBodySettings
        } else {
            return .page1HolisticDashboard
        }
    }

    static func archiveAndResetAllPageReceipts(explicitRound: Int? = nil) throws {
        for page in VitalStridePreviewPageTab.allCases {
            let receiptURL = URL(fileURLWithPath: "\(page.handoffDirectory)/receipts/preview-selection.json")
            try archiveAndResetReceipt(
                fileURL: receiptURL,
                label: page.goalSlug,
                defaultAppearance: page.defaultAppearance,
                explicitRound: explicitRound
            )
        }

        // Preserve the owner's previous Loop 8 selections before resetting the
        // layer receipts, so the new gallery never destroys historical feedback.
        let legacySlugs = [
            "vs-ui-l4-holistic-dashboard",
            "vs-ui-l1-heart-sleep-detail",
            "vs-ui-l2-workout-load-progression",
            "vs-ui-l1-steps-body-settings"
        ]
        for slug in legacySlugs {
            let receiptURL = URL(fileURLWithPath: "\(VitalStridePreviewPageTab.handoffRootDirectory)/\(slug)/receipts/preview-selection.json")
            try archiveAndResetReceipt(
                fileURL: receiptURL,
                label: slug,
                defaultAppearance: "light",
                explicitRound: explicitRound
            )
        }

        let rootReceipt = URL(fileURLWithPath: "\(VitalStridePreviewPageTab.handoffRootDirectory)/vs-layered-component-gallery/receipts/preview-selection.json")
        try archiveAndResetReceipt(
            fileURL: rootReceipt,
            label: "vs-layered-component-gallery",
            defaultAppearance: "light",
            explicitRound: explicitRound
        )
    }

    private static func archiveAndResetReceipt(
        fileURL: URL,
        label: String,
        defaultAppearance: String,
        explicitRound: Int?
    ) throws {
        let writer = PreviewSelectionReceiptWriter(fileURL: receiptURL(fileURL), defaultAppearance: defaultAppearance)
        let result = try writer.archiveAndResetRound(explicitRound: explicitRound, defaultAppearance: defaultAppearance)
        writer.flush()
        if let archived = result.archivedURL { print("Archived \(label) -> \(archived.path)") }
        print("Reset \(label) -> \(fileURL.path)")
    }

    private static func receiptURL(_ url: URL) -> URL { url }

    static func renderBoardSnapshot(page: VitalStridePreviewPageTab, to destination: URL) throws {
        let size = CGSize(width: 2140, height: 1440)
        let receiptURL = URL(fileURLWithPath: "\(page.handoffDirectory)/receipts/preview-selection.json")
        let receipt = PreviewSelectionReceiptWriter(
            fileURL: receiptURL,
            defaultAppearance: page.defaultAppearance
        ).currentReceipt
        let scheme: ColorScheme = receipt.appearance == "dark" ? .dark : .light
        let isDark = scheme == .dark
        let resolvedTheme = Theme(seed: .teal, neutral: .slate, isDark: isDark)

        let view = VitalStridePreviewHostBoard(initialPage: page)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.vsPreviewSnapshotMode, true)
            .environment(\.colorScheme, scheme)
            .environment(\.theme, resolvedTheme)
            .background(resolvedTheme.canvas)

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        renderer.proposedSize = ProposedViewSize(size)
        if let cgImage = renderer.cgImage,
           let writer = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(writer, cgImage, nil)
            if CGImageDestinationFinalize(writer) {
                print(destination.path)
                return
            }
        }

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw NSError(domain: "VitalStridePreviewHost", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to rasterize board"])
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "VitalStridePreviewHost", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
        }
        try png.write(to: destination, options: .atomic)
        print(destination.path)
    }

    static func renderAllPageSnapshots(into baseDir: URL) throws {
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        for page in VitalStridePreviewPageTab.allCases {
            let outURL = baseDir.appendingPathComponent(page.snapshotFilename)
            try renderBoardSnapshot(page: page, to: outURL)

            let goalSnapshotDir = URL(fileURLWithPath: "\(page.handoffDirectory)/snapshots", isDirectory: true)
            try FileManager.default.createDirectory(at: goalSnapshotDir, withIntermediateDirectories: true)
            let copyURL = goalSnapshotDir.appendingPathComponent(page.snapshotFilename)
            if FileManager.default.fileExists(atPath: copyURL.path) {
                try? FileManager.default.removeItem(at: copyURL)
            }
            try FileManager.default.copyItem(at: outURL, to: copyURL)
        }
    }
}

@MainActor
final class VitalStridePreviewHostAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let coordinator: VitalStridePreviewBoardCoordinator

    init(initialPage: VitalStridePreviewPageTab) {
        self.coordinator = VitalStridePreviewBoardCoordinator(initialPage: initialPage)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = VitalStridePreviewHostBoard(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: contentView)
        let win = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1680, height: 1020),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "VitalStride 4-Layer Component Gallery · 120Hz Native SwiftUI 10-Up Preview Host"
        win.contentViewController = hostingController
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = win
    }

    func applicationWillTerminate(_ notification: Notification) {
        for ctrl in coordinator.allControllers {
            ctrl.flush()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

DispatchQueue.main.async {
    MainActor.assumeIsolated {
        VitalStridePreviewHostRunner.run()
    }
}
RunLoop.main.run()
