import AIService
import DesignKit
import Foundation
import HealthKitService
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
        #expect(["1h 24m", "1小时24分"].contains(HeartSleepFormatting.duration(sleep.debt.sevenDayDebt)))
        #expect(["2h 36m", "2小时36分"].contains(HeartSleepFormatting.duration(sleep.debt.fourteenDayDebt)))
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
        #expect(["Intensification", "强化期"].contains(HeartSleepFormatting.phase(state.report?.l3.mesocyclePhase ?? AIService.MesocyclePhase.deload)))
        #expect(["Local rules", "生理规则引擎"].contains(HeartSleepFormatting.provider(state.provider)))
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

        let summarySource = try String(contentsOf: URL(fileURLWithPath: Self.sourcePath("../FourLayerSummaryComponents.swift")), encoding: .utf8)
        #expect(summarySource.contains("PlatformHealthDetailActionButton"))
        #expect(summarySource.contains("x-apple-health://"))
        #expect(summarySource.contains("Compact7DayTrendPopover"))
        #expect(!summarySource.contains("displayLimit = 200"))
    }

    @Test("Loading a real cache maps empty and populated heart-sleep evidence")
    func loadFromHealthDataCache() async {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let emptyState = HeartSleepCouplingState()
        await emptyState.load(cache: HealthDataCache(dataProvider: StubHealthProvider(points: [])), generatedAt: generatedAt)
        #expect(emptyState.loadState == .empty)

        let sleepStart = generatedAt.addingTimeInterval(-8 * 3600)
        let points = [
            testPoint(.restingHeartRate, value: 54, date: generatedAt.addingTimeInterval(-3600), unit: "count/min"),
            testPoint(.heartRateVariabilitySDNN, value: 68, date: generatedAt.addingTimeInterval(-3600), unit: "ms"),
            testPoint(.heartRate, value: 164, date: generatedAt.addingTimeInterval(-120), unit: "count/min"),
            testPoint(.heartRate, value: 132, date: generatedAt.addingTimeInterval(-60), unit: "count/min"),
            testPoint(.sleepAnalysis, value: 1, date: sleepStart, duration: 3600, unit: "category", stage: .asleepDeep),
            testPoint(.sleepAnalysis, value: 1, date: sleepStart.addingTimeInterval(3600), duration: 5400, unit: "category", stage: .asleepCore),
            testPoint(.sleepAnalysis, value: 1, date: sleepStart.addingTimeInterval(9000), duration: 3600, unit: "category", stage: .asleepREM),
            testPoint(.sleepAnalysis, value: 1, date: sleepStart.addingTimeInterval(12600), duration: 600, unit: "category", stage: .awake),
            testPoint(.sleepAnalysis, value: 1, date: sleepStart, duration: 13200, unit: "category", stage: .inBed),
        ]
        let state = HeartSleepCouplingState()
        await state.load(cache: HealthDataCache(dataProvider: StubHealthProvider(points: points)), generatedAt: generatedAt)
        #expect(state.loadState == .populated)
        #expect(state.snapshot?.heart.hrvCorridor.currentMilliseconds != nil)
        #expect(state.snapshot?.sleep.debt.observedNightCount7d ?? 0 > 0)
        #expect(state.report?.l2.contains { $0.relationship == "sleepTrainingCoupling" } == true)
    }

    @Test("Heart and sleep detail sources keep logs free of health values")
    func privacyLogContract() throws {
        for name in ["HeartSleepCouplingDetailView.swift", "HeartRateSection.swift", "SleepSection.swift"] {
            let source = try String(contentsOf: URL(fileURLWithPath: Self.sourcePath(name)), encoding: .utf8)
            for site in HeartRatePrivacyLoggingTests.logCallSites(in: source) {
                #expect(HeartRatePrivacyLoggingTests.forbiddenTokens(inArgument: site.argument).isEmpty)
            }
        }
    }

    #if canImport(UIKit)
    @Test("Exports four states in light and dark simulator windows")
    func exportsFourStatesInBothAppearances() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "vs-heart-sleep-snapshots-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exportDirectory = ProcessInfo.processInfo.environment["VS_UI_L1_SNAPSHOT_DIR"]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        if let exportDirectory {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }
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
                guard let data = image.pngData() else { throw SnapshotError.encodingFailed }
                try data.write(to: directory.appendingPathComponent("\(stateName)-\(appearance).png"), options: .atomic)
                if let exportDirectory {
                    try data.write(to: exportDirectory.appendingPathComponent("\(stateName)-\(appearance).png"), options: .atomic)
                }
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }
    #endif

    private enum SnapshotError: Error { case encodingFailed }

    private static func sourcePath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/DataSections/\(name)").path
    }
}

private func testPoint(
    _ sampleType: HealthSampleType,
    value: Double,
    date: Date,
    duration: TimeInterval = 60,
    unit: String,
    stage: SleepStage? = nil
) -> HealthDataPoint {
    HealthDataPoint(
        id: UUID(),
        sampleType: sampleType,
        startDate: date,
        endDate: date.addingTimeInterval(duration),
        value: value,
        unit: unit,
        sleepStage: stage,
        sourceName: "HeartSleepTest"
    )
}

private struct StubHealthProvider: HealthDataProviding {
    let points: [HealthDataPoint]

    func fetchData(for sampleType: HealthSampleType, dateRange: DateInterval?) async throws -> HealthFetchResult {
        HealthFetchResult(dataPoints: points.filter { $0.sampleType == sampleType }, deletedObjectIDs: [])
    }
}
