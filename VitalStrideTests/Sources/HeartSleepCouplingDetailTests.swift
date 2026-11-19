import AIService
import DesignKit
import Foundation
import SwiftUI
import Testing
import VitalModels
#if canImport(UIKit)
import UIKit
#endif
@testable import VitalStride

@Suite("Heart and sleep coupling detail")
@MainActor
struct HeartSleepCouplingDetailTests {
    @Test("State helpers preserve all four load states")
    func stateTransitions() {
        let state = HeartSleepCouplingState.preview()
        #expect(state.loadState == .populated)
        #expect(state.report?.l3.recommendedIntensityCap == 0.85)
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

    @Test("Heart corridor, recovery, zones, and sleep formatting remain numeric-safe")
    func metricFormatting() {
        let heart = HeartSleepCouplingState.preview().heart
        #expect(heart.hrvCorridor.isWithinCorridor)
        #expect(HeartSleepFormatting.signed(heart.restingHeartRate.deltaFromBaselineBPM) == "-3")
        #expect(HeartSleepFormatting.number(heart.recovery.oneMinuteDropBPM) == "32")
        #expect(HeartSleepFormatting.number(heart.recovery.twoMinuteDropBPM) == "49")
        #expect(heart.zoneDistribution.totalDuration > 0)
        let totalZoneRatio = VitalModels.HeartRateZone.allCases.reduce(0.0) { partial, zone in
            partial + heart.zoneDistribution.duration(in: zone) / heart.zoneDistribution.totalDuration
        }
        #expect(abs(totalZoneRatio - 1) < 0.001)

        let sleep = HeartSleepCouplingState.preview().sleep
        #expect(HeartSleepFormatting.percent(sleep.architecture.sleepEfficiency) == "92%")
        #expect(HeartSleepFormatting.duration(sleep.debt.sevenDayDebt) == "1h 24m")
        #expect(HeartSleepFormatting.duration(sleep.debt.fourteenDayDebt) == "2h 36m")
        #expect(sleep.debt.observedNightCount7d == 7)
        #expect(sleep.debt.observedNightCount14d == 14)
    }

    @Test("Coupling report exposes severity, intensity cap, phase, and provenance")
    func couplingReport() {
        let state = HeartSleepCouplingState.preview()
        let insight = state.report?.l2.first
        #expect(insight?.relationship == "sleepTrainingCoupling")
        #expect(insight?.severity == .normal)
        #expect(HeartSleepFormatting.percent(state.report?.l3.recommendedIntensityCap ?? 0) == "85%")
        #expect(HeartSleepFormatting.phase(state.report?.l3.mesocyclePhase ?? AIService.MesocyclePhase.deload) == "Intensification")
        #expect(HeartSleepFormatting.provider(state.provider) == "Local rules")
    }

    @Test("Page 2 source has no raw key leak, numeric ellipsis, or nested button")
    func sourceContract() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: Self.sourcePath("HeartSleepCouplingDetailView.swift")), encoding: .utf8)
        #expect(!source.contains("Text(\"heart_sleep_"))
        #expect(!source.contains("Text(\"coupling_"))
        #expect(!source.contains("…"))
        #expect(!source.contains("Button { Button"))
        #expect(!source.contains("@unchecked Sendable"))
        #expect(!source.contains("nonisolated(unsafe)"))
        #expect(!source.contains("try!"))
    }

    #if canImport(UIKit)
    @Test("Exports four states in light and dark simulator windows")
    func exportsFourStatesInBothAppearances() throws {
        let directory = URL(fileURLWithPath: "/Users/lee/Development/handoff/vs-ui-l1-heart-sleep-detail/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let states: [(String, (HeartSleepCouplingState) -> Void)] = [
            ("populated", { _ in }),
            ("empty", { $0.markEmpty() }),
            ("loading", { $0.markLoading() }),
            ("error", { $0.markError() }),
        ]
        for (stateName, mutate) in states {
            for (appearance, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
                let state = HeartSleepCouplingState.preview()
                mutate(state)
                let root = NavigationStack { HeartSleepCouplingDetailView(state: state) }
                    .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: scheme == .dark))
                    .preferredColorScheme(scheme)
                    .frame(width: 393, height: 852)
                let controller = UIHostingController(rootView: root)
                let window = try overviewSnapshotWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
                window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = true
                format.preferredRange = .standard
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 393, height: 852), format: format)
                let image = renderer.image { _ in _ = controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true) }
                try image.pngData()?.write(to: directory.appendingPathComponent("\(stateName)-\(appearance).png"))
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }
    #endif

    private static func sourcePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/DataSections/\(name)").path
    }
}
