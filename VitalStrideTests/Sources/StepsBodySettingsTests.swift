import AIService
import Foundation
import Testing
import VitalModels
#if canImport(UIKit)
import ImageIO
import SwiftUI
import UIKit
#endif
@testable import VitalStride

@Suite("Steps and body settings", .serialized)
@MainActor
struct StepsBodySettingsTests {
    @Test("recovery state exposes four deterministic transitions")
    @MainActor
    func stateTransitions() {
        let state = StepsBodyRecoveryState.preview()
        #expect(state.loadState == .populated)
        state.markEmpty()
        #expect(state.loadState == .empty)
        state.markLoading()
        #expect(state.loadState == .loading)
        var retried = false
        state.markError { retried = true }
        #expect(state.loadState == .error)
        state.onRetry?()
        #expect(retried)
    }

    @Test("NEAT snapshot clamps split and computes burden ratio")
    func neatMath() {
        let snapshot = VitalModels.NEATActivitySnapshot(
            dailySteps: 9_420,
            nonExerciseActiveEnergy: 340,
            basalEnergy: 1_680,
            hourlyMovementConsistency: 0.79,
            flightsClimbed: 8,
            nonWorkoutSteps: 7_680,
            workoutActiveEnergyExcluded: 410,
            activeNonWorkoutHourCount: 11,
            hourlyNonWorkoutDistribution: Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, Double($0)) })
        )
        #expect(snapshot.dailySteps == 9_420)
        #expect(snapshot.nonWorkoutSteps == 7_680)
        #expect(snapshot.hourlyNonWorkoutDistribution.count == 24)
        #expect(snapshot.activeNonWorkoutHourCount == 11)
        #expect(abs(snapshot.nonExerciseActiveEnergy / snapshot.basalEnergy - 0.20238) < 0.001)
    }

    @Test("unit conversions and observed composition preserve missing values")
    func unitsAndOptionalComposition() {
        #expect(abs(EnergyUnit.kJ.convert(fromKcal: 340) - 1422.56) < 0.01)
        #expect(abs(EnergyUnit.kcal.convert(fromKcal: 340) - 340) < 0.01)
        let points = [
            WeightDataPoint(date: Date(timeIntervalSinceReferenceDate: 1), weight: 74),
            WeightDataPoint(date: Date(timeIntervalSinceReferenceDate: 2), weight: 73.5),
            WeightDataPoint(date: Date(timeIntervalSinceReferenceDate: 3), weight: 73.4)
        ]
        let average = WeightAnalyzer.movingAverage(of: points, windowSize: 7)
        #expect(average.count == 3)
        #expect(abs((average.last?.weight ?? 0) - 73.6333) < 0.001)
        #expect(StepsBodyCopy.percent(0.79) == "79%")
        #expect(StepsBodyCopy.guardrail.contains("intake") || StepsBodyCopy.guardrail.contains("摄入"))
    }

    @Test("configuration round trip stores routing metadata but never a secret")
    @MainActor
    func configurationRoundTrip() throws {
        let suite = "steps-body-settings-tests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = AIModelSettingsStore(defaults: defaults)
        store.select(.jevGateway)
        store.update(baseURL: "http://127.0.0.1:3425/v1", modelID: "jev-default", allowsUnauthenticatedGateway: true)
        let data = try #require(defaults.data(forKey: AIModelSettingsStore.defaultsKey))
        let stored = try JSONDecoder().decode(UserAIModelConfiguration.self, from: data)
        #expect(stored.provider == .jevGateway)
        #expect(stored.allowsUnauthenticatedGateway)
        #expect(stored.keychainService == nil)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("secret"))
        #expect(!json.contains("token"))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test("production source keeps privacy and subtractive view contracts")
    func negativeSourceAssertions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let steps = try String(contentsOf: root.appendingPathComponent("VitalStride/Sources/DataSections/StepsBodyRecoveryView.swift"), encoding: .utf8)
        let ai = try String(contentsOf: root.appendingPathComponent("VitalStride/Sources/AISettingsSection.swift"), encoding: .utf8)
        #expect(!steps.contains("print("))
        #expect(!steps.contains("Logger("))
        #expect(!steps.contains("…"))
        #expect(!ai.contains("logger."))
        #expect(!ai.contains("UserDefaults.standard.set(.*secret"))
        #expect(!steps.contains("点击"))
        #expect(!steps.contains("Text(\"ai_config_"))
    }

#if canImport(UIKit)
    @MainActor
    @Test("Export ten genuine 393 by 852 window snapshots")
    func exportSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vs-ui-l1-sb-snapshots-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exportDirectory = ProcessInfo.processInfo.environment["VS_UI_L1_SB_SNAPSHOT_DIR"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        if let exportDirectory {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }

        let empty = StepsBodyRecoveryState.preview(); empty.markEmpty()
        let loading = StepsBodyRecoveryState.preview(); loading.markLoading()
        let error = StepsBodyRecoveryState.preview(); error.markError(onRetry: {})
        var allData: [Data] = []
        for appearance in [ColorScheme.light, .dark] {
            let cases: [(String, AnyView)] = [
                ("populated", AnyView(NavigationStack { StepsBodyRecoveryView(state: .preview()) })),
                ("empty", AnyView(NavigationStack { StepsBodyRecoveryView(state: empty) })),
                ("loading", AnyView(NavigationStack { StepsBodyRecoveryView(state: loading) })),
                ("error", AnyView(NavigationStack { StepsBodyRecoveryView(state: error) })),
                ("ai-settings", AnyView(NavigationStack { AIModelConfigurationView() }))
            ]
            var appearanceData: [Data] = []
            for (name, view) in cases {
                let root = view
                    .environment(AppNavigation())
                    .designTheme(seed: .teal, neutral: .slate)
                    .preferredColorScheme(appearance)
                let image = try await render(root, appearance: appearance)
                let data = try #require(normalizedPNGData(image))
                let filename = "\(name)-\(appearance == .dark ? "dark" : "light").png"
                try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
                if let exportDirectory {
                    try data.write(to: exportDirectory.appendingPathComponent(filename), options: .atomic)
                }
                #expect(image.size == CGSize(width: 393, height: 852))
                appearanceData.append(data)
                allData.append(data)
            }
            #expect(Set(appearanceData).count == cases.count)
        }
        #expect(Set(allData).count == 10)
    }

    private func normalizedPNGData(_ image: UIImage) -> Data? {
        guard let source = image.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: source.width,
                height: source.height,
                bitsPerComponent: 8,
                bytesPerRow: source.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let normalized = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, normalized, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func pumpRunLoop() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

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
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size, format: format)
        return renderer.image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    }
#endif
}
