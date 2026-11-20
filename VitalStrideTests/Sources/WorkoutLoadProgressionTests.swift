import AIService
import Foundation
import Testing
import VitalModels
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

@testable import VitalStride

@Suite("Workout Load Progression", .serialized)
@MainActor
struct WorkoutLoadProgressionTests {
    @Test("Preview snapshot carries PMC, zones, aerobic and periodization evidence")
    func previewEvidence() {
        let snapshot = WorkoutLoadProgressionState.previewSnapshot
        #expect(snapshot.trainingLoad.chronicTrainingLoad == 64.7)
        #expect(snapshot.trainingLoad.acuteTrainingLoad == 58.4)
        #expect(snapshot.trainingLoad.trainingStressBalance == 6.3)
        #expect(snapshot.trainingLoad.acuteChronicWorkloadRatio == 0.9)
        #expect(snapshot.trainingLoad.trimp == 312)
        #expect(snapshot.trainingLoad.tss == 268)
        #expect(snapshot.trainingLoad.recentTrajectory.count == 14)
        #expect(snapshot.heart.zoneDistribution.totalDuration == 12_000)
        #expect(snapshot.heart.zoneDistribution.zone1Duration + snapshot.heart.zoneDistribution.zone2Duration == 8_640)
        #expect(snapshot.aerobic.efficiencyFactor == 0.086)
        #expect(snapshot.aerobic.aerobicDecouplingPercentage == 3.4)
        #expect(snapshot.aerobic.vo2Max == 51.4)
        #expect(WorkoutLoadProgressionState.previewReport.l3.mesocyclePhase == .intensification)
        #expect(WorkoutLoadProgressionState.previewReport.l3.recommendedIntensityCap == 0.85)
    }

    @Test("Load state transitions preserve the four-state contract")
    func loadStates() {
        let populated = WorkoutLoadProgressionState.preview()
        #expect(populated.loadState == .populated)
        populated.markEmpty()
        #expect(populated.loadState == .empty)
        populated.markLoading()
        #expect(populated.loadState == .loading)
        var retried = false
        populated.markError { retried = true }
        #expect(populated.loadState == .error)
        populated.onRetry?()
        #expect(retried)
    }

    @Test("All AI providers have distinct localized labels")
    func providerLabels() {
        let labels = PluggableAIProvider.allCases.map(WorkoutLoadCopy.provider)
        #expect(Set(labels).count == PluggableAIProvider.allCases.count)
        #expect(labels.count == 4)
    }

    @Test("Zone and aerobic classification math is stable")
    func classificationMath() {
        let zones = WorkoutLoadProgressionState.previewSnapshot.heart.zoneDistribution
        let total = zones.totalDuration
        let low = (zones.zone1Duration + zones.zone2Duration) / total
        let moderate = zones.zone3Duration / total
        let high = (zones.zone4Duration + zones.zone5Duration) / total
        #expect(abs(low - 0.72) < 0.001)
        #expect(abs(moderate - 0.11) < 0.001)
        #expect(abs(high - 0.17) < 0.001)
        #expect((WorkoutLoadProgressionState.previewSnapshot.aerobic.aerobicDecouplingPercentage ?? 0) <= 5)
        #expect((WorkoutLoadProgressionState.previewSnapshot.trainingLoad.acuteChronicWorkloadRatio ?? 0) >= 0.8)
    }

    @Test("Source stays within the privacy and visual redlines")
    func negativeSourceAssertions() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("VitalStride/Sources/DataSections/WorkoutLoadProgressionView.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        #expect(!source.contains("print("))
        #expect(!source.contains("Logger("))
        #expect(!source.contains("os_log"))
        #expect(!source.contains("try!"))
        #expect(!source.contains("as!"))
        #expect(!source.contains("fatalError("))
        #expect(!source.contains("…"))
        #expect(!source.contains("点击"))
        #expect(!source.contains("执行步骤树"))
        #expect(source.components(separatedBy: "Button(").count - 1 == 0 || !source.contains("Button(\n                    Button("))
    }

#if canImport(UIKit)
    @Test("Export populated, empty, loading and error light/dark PNG evidence")
    func exportSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vs-workout-load-snapshots-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exportDirectory = ProcessInfo.processInfo.environment["VS_UI_L2_SNAPSHOT_DIR"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        if let exportDirectory {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }
        let cases: [(String, WorkoutLoadProgressionState)] = [
            ("populated", .preview()),
            ("empty", { let value = WorkoutLoadProgressionState.preview(); value.markEmpty(); return value }()),
            ("loading", { let value = WorkoutLoadProgressionState.preview(); value.markLoading(); return value }()),
            ("error", { let value = WorkoutLoadProgressionState.preview(); value.markError(onRetry: {}); return value }()),
        ]
        for (name, state) in cases {
            for appearance in [ColorScheme.light, .dark] {
                let root = NavigationStack { WorkoutLoadProgressionView(state: state) }
                    .environment(AppNavigation())
                    .designTheme(seed: .teal, neutral: .slate)
                    .preferredColorScheme(appearance)
                let image = try await render(root, appearance: appearance)
                let filename = "\(name)-\(appearance == .dark ? "dark" : "light").png"
                let data = try #require(image.pngData())
                try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
                if let exportDirectory {
                    try data.write(to: exportDirectory.appendingPathComponent(filename), options: .atomic)
                }
                #expect(image.size == CGSize(width: 393, height: 852))
            }
        }
    }

    private func pumpRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    private func render<Content: View>(_ content: Content, appearance: ColorScheme) async throws -> UIImage {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = try #require(scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: content)
        let style: UIUserInterfaceStyle = appearance == .dark ? .dark : .light
        window.overrideUserInterfaceStyle = style
        controller.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        for _ in 0..<4 {
            try await Task.sleep(for: .milliseconds(50))
            pumpRunLoop()
            controller.view.layoutIfNeeded()
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format)
        return renderer.image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    }
#endif
}
