import Foundation
import HealthKit
import HealthKitService
import SwiftData
import SwiftUI
import Testing

@testable import VitalStride

// MARK: - HealthSnapshotData Tests

@Suite("HealthSnapshotData Tests")
struct HealthSnapshotDataTests {
    @Test("hasAnyData returns false when all nil")
    func hasAnyDataAllNil() {
        let data = HealthSnapshotData(todaySteps: nil, averageBPM: nil, lastNightSleep: nil, latestWeight: nil)
        #expect(!data.hasAnyData)
    }

    @Test("hasAnyData returns true when steps present")
    func hasAnyDataWithSteps() {
        let data = HealthSnapshotData(todaySteps: 5000, averageBPM: nil, lastNightSleep: nil, latestWeight: nil)
        #expect(data.hasAnyData)
    }

    @Test("hasAnyData returns true when heart rate present")
    func hasAnyDataWithHeartRate() {
        let data = HealthSnapshotData(todaySteps: nil, averageBPM: 72, lastNightSleep: nil, latestWeight: nil)
        #expect(data.hasAnyData)
    }

    @Test("hasAnyData returns true when sleep present")
    func hasAnyDataWithSleep() {
        let data = HealthSnapshotData(todaySteps: nil, averageBPM: nil, lastNightSleep: 7 * 3600, latestWeight: nil)
        #expect(data.hasAnyData)
    }

    @Test("hasAnyData returns true when weight present")
    func hasAnyDataWithWeight() {
        let data = HealthSnapshotData(todaySteps: nil, averageBPM: nil, lastNightSleep: nil, latestWeight: 75.5)
        #expect(data.hasAnyData)
    }

    @Test("hasAnyData returns true when all present")
    func hasAnyDataAllPresent() {
        let data = HealthSnapshotData(todaySteps: 8000, averageBPM: 68, lastNightSleep: 6 * 3600, latestWeight: 72.0)
        #expect(data.hasAnyData)
    }
}

// MARK: - HealthSnapshotState Tests

@Suite("HealthSnapshotState Tests")
struct HealthSnapshotStateTests {
    @Test("Initial state is loading with no data")
    @MainActor
    func initialState() {
        let state = HealthSnapshotState()
        #expect(state.isLoading)
        #expect(!state.isAuthorized)
        #expect(!state.hasAnyHealthData)
    }

    @Test("Load sets isAuthorized false when health data not available")
    @MainActor
    func loadUnauthorized() async {
        let mock = MockHealthStore()
        mock.authorizationRequestStatus = .shouldRequest
        let defaults = UserDefaults(suiteName: "SnapshotTest_\(UUID().uuidString)")!
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test")
        let service = HealthKitService(healthStore: mock, anchorStore: anchors, deviceIdentifier: "test")
        let cache = HealthDataCache(dataProvider: service)

        let state = HealthSnapshotState()
        await state.load(cache: cache, service: service)

        #expect(!state.isLoading)
        #expect(!state.isAuthorized)
        #expect(!state.hasAnyHealthData)
    }

    @Test("Load populates steps when authorized and data available")
    @MainActor
    func loadWithSteps() async {
        let mock = MockHealthStore()
        mock.authorizationRequestStatus = .unnecessary
        let now = Date()
        let sample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 5000),
            start: now.addingTimeInterval(-3600),
            end: now
        )
        mock.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [sample], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 1)
        )
        setupEmptyResults(for: mock, except: .stepCount)

        let defaults = UserDefaults(suiteName: "SnapshotTest_\(UUID().uuidString)")!
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test")
        let service = HealthKitService(healthStore: mock, anchorStore: anchors, deviceIdentifier: "test")
        let cache = HealthDataCache(dataProvider: service)

        let state = HealthSnapshotState()
        await state.load(cache: cache, service: service)

        #expect(!state.isLoading)
        #expect(state.isAuthorized)
        #expect(state.hasAnyHealthData)
        #expect(state.snapshot.todaySteps != nil)
    }

    @Test("Load populates heart rate when authorized and data available")
    @MainActor
    func loadWithHeartRate() async {
        let mock = MockHealthStore()
        mock.authorizationRequestStatus = .unnecessary
        let now = Date()
        let sample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 72),
            start: now.addingTimeInterval(-600),
            end: now
        )
        mock.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [sample], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 1)
        )
        setupEmptyResults(for: mock, except: .heartRate)

        let defaults = UserDefaults(suiteName: "SnapshotTest_\(UUID().uuidString)")!
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test")
        let service = HealthKitService(healthStore: mock, anchorStore: anchors, deviceIdentifier: "test")
        let cache = HealthDataCache(dataProvider: service)

        let state = HealthSnapshotState()
        await state.load(cache: cache, service: service)

        #expect(state.isAuthorized)
        #expect(state.snapshot.averageBPM == 72)
    }

    @Test("Load returns nil for all metrics when authorized but no data")
    @MainActor
    func loadAuthorizedNoData() async {
        let mock = MockHealthStore()
        mock.authorizationRequestStatus = .unnecessary
        for sampleType in HealthSampleType.allCases {
            mock.queryResults[sampleType.hkSampleType] = AnchoredQueryResult(
                samples: [], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 0)
            )
        }

        let defaults = UserDefaults(suiteName: "SnapshotTest_\(UUID().uuidString)")!
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test")
        let service = HealthKitService(healthStore: mock, anchorStore: anchors, deviceIdentifier: "test")
        let cache = HealthDataCache(dataProvider: service)

        let state = HealthSnapshotState()
        await state.load(cache: cache, service: service)

        #expect(state.isAuthorized)
        #expect(!state.hasAnyHealthData)
        #expect(state.snapshot.todaySteps == nil)
        #expect(state.snapshot.averageBPM == nil)
        #expect(state.snapshot.lastNightSleep == nil)
        #expect(state.snapshot.latestWeight == nil)
    }

    @Test("Load populates all metrics when all data available")
    @MainActor
    func loadAllMetrics() async {
        let mock = MockHealthStore()
        mock.authorizationRequestStatus = .unnecessary
        let now = Date()

        let stepSample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 8000),
            start: now.addingTimeInterval(-7200),
            end: now
        )
        mock.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [stepSample], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let hrSample = HKQuantitySample(
            type: HKQuantityType(.heartRate),
            quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: 68),
            start: now.addingTimeInterval(-300),
            end: now
        )
        mock.queryResults[HKQuantityType(.heartRate)] = AnchoredQueryResult(
            samples: [hrSample], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let sleepStart = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: now.addingTimeInterval(-86400))!
        let sleepEnd = sleepStart.addingTimeInterval(7 * 3600)
        let sleepSample = HKCategorySample(
            type: HKCategoryType(.sleepAnalysis),
            value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: sleepStart,
            end: sleepEnd
        )
        mock.queryResults[HKCategoryType(.sleepAnalysis)] = AnchoredQueryResult(
            samples: [sleepSample], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 1)
        )

        let weightSample = HKQuantitySample(
            type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 75.5),
            start: now.addingTimeInterval(-86400),
            end: now.addingTimeInterval(-86400)
        )
        mock.queryResults[HKQuantityType(.bodyMass)] = AnchoredQueryResult(
            samples: [weightSample], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 1)
        )

        mock.queryResults[HKQuantityType(.activeEnergyBurned)] = AnchoredQueryResult(
            samples: [], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 0)
        )

        let defaults = UserDefaults(suiteName: "SnapshotTest_\(UUID().uuidString)")!
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test")
        let service = HealthKitService(healthStore: mock, anchorStore: anchors, deviceIdentifier: "test")
        let cache = HealthDataCache(dataProvider: service)

        let state = HealthSnapshotState()
        await state.load(cache: cache, service: service)

        #expect(state.isAuthorized)
        #expect(state.hasAnyHealthData)
        #expect(state.snapshot.todaySteps != nil)
        #expect(state.snapshot.averageBPM == 68)
        #expect(state.snapshot.latestWeight == 75.5)
    }

    @Test("forceRefresh bypasses cache and returns fresh HealthKit data")
    @MainActor
    func forceRefreshBypassesCache() async {
        let mock = MockHealthStore()
        mock.authorizationRequestStatus = .unnecessary
        let now = Date()

        let staleSample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 5000),
            start: now.addingTimeInterval(-3600),
            end: now
        )
        mock.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [staleSample], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 1)
        )
        setupEmptyResults(for: mock, except: .stepCount)

        let defaults = UserDefaults(suiteName: "SnapshotTest_\(UUID().uuidString)")!
        let anchors = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test")
        let service = HealthKitService(healthStore: mock, anchorStore: anchors, deviceIdentifier: "test")
        let cache = HealthDataCache(dataProvider: service)

        let state = HealthSnapshotState()

        await state.load(cache: cache, service: service)
        #expect(state.snapshot.todaySteps == 5000)

        let freshSample = HKQuantitySample(
            type: HKQuantityType(.stepCount),
            quantity: HKQuantity(unit: .count(), doubleValue: 10000),
            start: now.addingTimeInterval(-1800),
            end: now
        )
        mock.queryResults[HKQuantityType(.stepCount)] = AnchoredQueryResult(
            samples: [freshSample], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 2)
        )

        await state.load(cache: cache, service: service)
        #expect(state.snapshot.todaySteps == 5000, "Default load should return cached stale data")

        await state.load(cache: cache, service: service, forceRefresh: true)
        #expect(state.snapshot.todaySteps == 10000, "forceRefresh should bypass cache and return fresh data")
    }
}

// MARK: - Overview Display Logic Tests

@Suite("Overview Display Logic Tests")
struct OverviewDisplayLogicTests {
    @Test("With health data and workouts, both sections shown")
    func healthAndWorkouts() {
        let snapshot = HealthSnapshotData(todaySteps: 5000, averageBPM: 72, lastNightSleep: nil, latestWeight: nil)
        let hasWorkouts = true
        let showHealth = snapshot.hasAnyData
        let showWorkouts = hasWorkouts
        let showEmpty = !showHealth && !showWorkouts

        #expect(showHealth)
        #expect(showWorkouts)
        #expect(!showEmpty)
    }

    @Test("With health data only, only health snapshot shown")
    func healthOnly() {
        let snapshot = HealthSnapshotData(todaySteps: 3000, averageBPM: nil, lastNightSleep: nil, latestWeight: nil)
        let hasWorkouts = false
        let showHealth = snapshot.hasAnyData
        let showWorkouts = hasWorkouts
        let showEmpty = !showHealth && !showWorkouts

        #expect(showHealth)
        #expect(!showWorkouts)
        #expect(!showEmpty)
    }

    @Test("With workout data only, only workout sections shown")
    func workoutsOnly() {
        let snapshot = HealthSnapshotData(todaySteps: nil, averageBPM: nil, lastNightSleep: nil, latestWeight: nil)
        let hasWorkouts = true
        let showHealth = snapshot.hasAnyData
        let showWorkouts = hasWorkouts
        let showEmpty = !showHealth && !showWorkouts

        #expect(!showHealth)
        #expect(showWorkouts)
        #expect(!showEmpty)
    }

    @Test("With no data, empty state shown")
    func noData() {
        let snapshot = HealthSnapshotData(todaySteps: nil, averageBPM: nil, lastNightSleep: nil, latestWeight: nil)
        let hasWorkouts = false
        let showHealth = snapshot.hasAnyData
        let showWorkouts = hasWorkouts
        let showEmpty = !showHealth && !showWorkouts

        #expect(!showHealth)
        #expect(!showWorkouts)
        #expect(showEmpty)
    }

    @Test("Unauthorized hides health snapshot even if hypothetically data exists")
    func unauthorizedHidesHealth() {
        let isAuthorized = false
        let snapshot = HealthSnapshotData(todaySteps: nil, averageBPM: nil, lastNightSleep: nil, latestWeight: nil)
        let showHealthSnapshot = isAuthorized && snapshot.hasAnyData
        #expect(!showHealthSnapshot)
    }
}

// MARK: - SummaryCard Preloaded Initializer Tests

@Suite("SummaryCard Preloaded Data Tests")
struct SummaryCardPreloadedTests {
    @Test("StepsSummaryCard accepts preloaded data")
    func stepsPreloaded() {
        _ = StepsSummaryCard(preloaded: 8000)
    }

    @Test("StepsSummaryCard accepts preloaded nil")
    func stepsPreloadedNil() {
        _ = StepsSummaryCard(preloaded: nil)
    }

    @Test("StepsSummaryCard default init is available")
    func stepsDefaultInit() {
        _ = StepsSummaryCard()
    }

    @Test("HeartRateSummaryCard accepts preloaded data")
    func heartRatePreloaded() {
        _ = HeartRateSummaryCard(preloaded: 72)
    }

    @Test("HeartRateSummaryCard accepts preloaded nil")
    func heartRatePreloadedNil() {
        _ = HeartRateSummaryCard(preloaded: nil)
    }

    @Test("HeartRateSummaryCard default init is available")
    func heartRateDefaultInit() {
        _ = HeartRateSummaryCard()
    }

    @Test("SleepSummaryCard accepts preloaded data")
    func sleepPreloaded() {
        _ = SleepSummaryCard(preloaded: 7 * 3600)
    }

    @Test("SleepSummaryCard accepts preloaded nil")
    func sleepPreloadedNil() {
        _ = SleepSummaryCard(preloaded: nil)
    }

    @Test("SleepSummaryCard default init is available")
    func sleepDefaultInit() {
        _ = SleepSummaryCard()
    }

    @Test("WeightSummaryCard accepts preloaded data")
    func weightPreloaded() {
        _ = WeightSummaryCard(preloaded: 75.5)
    }

    @Test("WeightSummaryCard accepts preloaded nil")
    func weightPreloadedNil() {
        _ = WeightSummaryCard(preloaded: nil)
    }

    @Test("WeightSummaryCard default init is available")
    func weightDefaultInit() {
        _ = WeightSummaryCard()
    }

    @Test("SummaryCardView is accessible as shared component")
    func summaryCardViewAccessible() {
        _ = SummaryCardView(
            title: "Test",
            systemImage: "star",
            color: .blue,
            isLoading: false
        ) {
            Text("Content")
        }
    }
}

// MARK: - SummaryCard Reuse Verification Tests

@Suite("SummaryCard Reuse Verification Tests")
struct SummaryCardReuseVerificationTests {
    @Test("OverviewView source references shared SummaryCard types")
    func overviewUsesSharedCards() throws {
        let overviewSource = try String(
            contentsOfFile: findSourceFile(named: "OverviewView.swift"),
            encoding: .utf8
        )
        #expect(overviewSource.contains("StepsSummaryCard(preloaded:"))
        #expect(overviewSource.contains("HeartRateSummaryCard(preloaded:"))
        #expect(overviewSource.contains("SleepSummaryCard(preloaded:"))
        #expect(overviewSource.contains("WeightSummaryCard(preloaded:"))
    }

    @Test("DataView source references shared SummaryCard types")
    func dataViewUsesSharedCards() throws {
        let dataViewSource = try String(
            contentsOfFile: findSourceFile(named: "DataView.swift"),
            encoding: .utf8
        )
        #expect(dataViewSource.contains("StepsSummaryCard()"))
        #expect(dataViewSource.contains("HeartRateSummaryCard()"))
        #expect(dataViewSource.contains("SleepSummaryCard()"))
        #expect(dataViewSource.contains("WeightSummaryCard()"))
    }

    @Test("OverviewView does not define its own metric card")
    func noLocalMetricCard() throws {
        let overviewSource = try String(
            contentsOfFile: findSourceFile(named: "OverviewView.swift"),
            encoding: .utf8
        )
        #expect(!overviewSource.contains("SnapshotMetricCard"))
    }

    @Test("Shared cards are defined in HealthSummaryCards, not in DataView or OverviewView")
    func cardsDefinedInSharedFile() throws {
        let sharedSource = try String(
            contentsOfFile: findSourceFile(named: "HealthSummaryCards.swift"),
            encoding: .utf8
        )
        #expect(sharedSource.contains("struct StepsSummaryCard"))
        #expect(sharedSource.contains("struct HeartRateSummaryCard"))
        #expect(sharedSource.contains("struct SleepSummaryCard"))
        #expect(sharedSource.contains("struct WeightSummaryCard"))
        #expect(sharedSource.contains("struct SummaryCardView"))

        let overviewSource = try String(
            contentsOfFile: findSourceFile(named: "OverviewView.swift"),
            encoding: .utf8
        )
        #expect(!overviewSource.contains("struct StepsSummaryCard"))
        #expect(!overviewSource.contains("struct SummaryCardView"))

        let dataViewSource = try String(
            contentsOfFile: findSourceFile(named: "DataView.swift"),
            encoding: .utf8
        )
        #expect(!dataViewSource.contains("struct StepsSummaryCard"))
        #expect(!dataViewSource.contains("struct SummaryCardView"))
    }

    @Test("Preloaded and self-loading initializers both exist for all four cards")
    func bothInitializersExist() {
        _ = StepsSummaryCard()
        _ = StepsSummaryCard(preloaded: 1000)
        _ = HeartRateSummaryCard()
        _ = HeartRateSummaryCard(preloaded: 70)
        _ = SleepSummaryCard()
        _ = SleepSummaryCard(preloaded: 3600.0)
        _ = WeightSummaryCard()
        _ = WeightSummaryCard(preloaded: 70.0)
    }
}

private func findSourceFile(named fileName: String) -> String {
    let fm = FileManager.default
    let startDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    let enumerator = fm.enumerator(
        at: startDir,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )

    while let url = enumerator?.nextObject() as? URL {
        if url.lastPathComponent == fileName, url.pathExtension == "swift" {
            return url.path
        }
    }

    return startDir.appendingPathComponent(fileName).path
}

// MARK: - Empty State Tests

@Suite("OverviewEmptyState Tests")
struct OverviewEmptyStateTests {
    @Test("OverviewEmptyState can be instantiated")
    func emptyStateInstantiable() {
        _ = OverviewEmptyState()
    }

    @Test("Empty state CTAs are Buttons, not standalone Labels")
    func ctasAreButtons() throws {
        let source = try String(
            contentsOfFile: findSourceFile(named: "OverviewView.swift"),
            encoding: .utf8
        )
        let emptyStateRange = source.range(of: "struct OverviewEmptyState")!
        let emptyStateCode = String(source[emptyStateRange.lowerBound...])

        #expect(emptyStateCode.contains("Button {"))
        #expect(emptyStateCode.contains(".accessibilityHint"))
    }
}

// MARK: - Test Helpers

private func setupEmptyResults(for mock: MockHealthStore, except excludedType: HealthSampleType) {
    for sampleType in HealthSampleType.allCases where sampleType != excludedType {
        mock.queryResults[sampleType.hkSampleType] = AnchoredQueryResult(
            samples: [], deletedObjectUUIDs: [], newAnchor: HKQueryAnchor(fromValue: 0)
        )
    }
}
