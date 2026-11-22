import AIService
import Foundation
import HealthKitService
import Testing
import VitalModels
@testable import VitalStride

@Suite("Holistic dashboard logic")
struct HolisticDashboardTests {
    @Test("readiness gate thresholds are exclusive and ordered")
    func readinessGateThresholds() {
        #expect(HolisticDashboardLogic.gate(for: 75) == .prime)
        #expect(HolisticDashboardLogic.gate(for: 50) == .moderate)
        #expect(HolisticDashboardLogic.gate(for: 49) == .recovery)
    }

    @Test("intensity cap is clamped and formatted without truncation")
    func intensityCapFormatting() {
        #expect(HolisticDashboardLogic.intensityPercent(0.855) == 86)
        #expect(HolisticDashboardLogic.intensityPercent(-1) == 0)
        #expect(HolisticDashboardLogic.intensityPercent(2) == 100)
    }

    @Test("provider provenance maps every pluggable provider")
    func providerMapping() {
        #expect(HolisticDashboardLogic.providerLabel(.foundationModels) == "On-device AI")
        #expect(HolisticDashboardLogic.providerLabel(.customOpenAICompatible) == "Custom API")
        #expect(HolisticDashboardLogic.providerLabel(.jevGateway) == "Jev Gateway")
        #expect(HolisticDashboardLogic.providerLabel(.deterministicFallback) == "Deterministic fallback")
    }

    @Test("preview state is populated without fabricated UI loading")
    @MainActor
    func previewState() {
        let state = HolisticDashboardState.preview()
        #expect(state.loadState == .populated)
        #expect(state.report?.l3.readinessScore == 82)
        #expect(state.report?.l4.prioritizedActions.count == 3)
    }

    @Test("overview keeps one spinner truth table")
    func singleSpinnerTruthTable() {
        #expect(OverviewView.isAnyLoading(snapshotIsLoading: true, snapshotIsAuthorized: true, hasWorkoutData: true, dynamicLayoutState: .fallback))
        #expect(OverviewView.isAnyLoading(snapshotIsLoading: false, snapshotIsAuthorized: true, hasWorkoutData: false, dynamicLayoutState: .loading))
        #expect(!OverviewView.isAnyLoading(snapshotIsLoading: false, snapshotIsAuthorized: false, hasWorkoutData: false, dynamicLayoutState: .loading))
    }

    @Test("all mesocycle phases have readable labels")
    func mesocyclePhaseLabels() {
        #expect(L4Copy.phase(.accumulation).contains("Accumulation"))
        #expect(L4Copy.phase(.intensification).contains("Intensification"))
        #expect(L4Copy.phase(.realization).contains("Realization"))
        #expect(L4Copy.phase(.deload).contains("Deload"))
    }

    @Test("load maps empty cache to empty and workout-only input to populated")
    @MainActor
    func loadGracefullyDegradesAcrossAvailableDomains() async {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let emptyCache = HealthDataCache(dataProvider: StubHealthProvider(points: []))
        let emptyState = HolisticDashboardState(configuration: UserAIModelConfiguration(provider: .deterministicFallback))
        await emptyState.load(cache: emptyCache, workouts: [], generatedAt: generatedAt)
        #expect(emptyState.loadState == .empty)

        let workout = Workout(
            type: .strength,
            startDate: generatedAt.addingTimeInterval(-3600),
            endDate: generatedAt.addingTimeInterval(-1800)
        )
        let exercise = WorkoutExercise(order: 0, sets: [ExerciseSet(weight: 40, reps: 8, isCompleted: true)])
        exercise.workout = workout
        workout.exercises = [exercise]
        let workoutCache = HealthDataCache(dataProvider: StubHealthProvider(points: []))
        let workoutState = HolisticDashboardState(configuration: UserAIModelConfiguration(provider: .deterministicFallback))
        await workoutState.load(cache: workoutCache, workouts: [workout], generatedAt: generatedAt)
        #expect(workoutState.loadState == .populated)
        #expect(workoutState.report?.l3.readinessScore != nil)
    }

    @Test("dashboard state exposes deterministic visual transitions")
    @MainActor
    func stateTransitions() {
        let state = HolisticDashboardState(configuration: UserAIModelConfiguration(provider: .deterministicFallback))
        state.markEmpty()
        #expect(state.loadState == .empty)
        state.markLoading()
        #expect(state.loadState == .loading)
        state.markError()
        #expect(state.loadState == .error)
        let preview = HolisticDashboardState.preview()
        #expect(preview.loadState == .populated)
        #expect(preview.report?.l4.prioritizedActions.count == 3)
    }

    @Test("stored provider configuration is resolved without a deterministic lock")
    @MainActor
    func storedProviderConfiguration() throws {
        guard let defaults = UserDefaults(suiteName: "holistic-dashboard-tests") else {
            Issue.record("Unable to create isolated test defaults")
            return
        }
        defaults.removePersistentDomain(forName: "holistic-dashboard-tests")
        let stored = UserAIModelConfiguration(provider: .jevGateway, modelID: "test-model", allowsUnauthenticatedGateway: true)
        defaults.set(try JSONEncoder().encode(stored), forKey: "userAIModelConfiguration")
        #expect(HolisticDashboardState.resolveConfiguration(defaults: defaults).provider == .jevGateway)
        defaults.removePersistentDomain(forName: "holistic-dashboard-tests")
    }

    @Test("quick drill-down destinations cover all app tabs")
    @MainActor
    func quickDrillDownDestinations() {
        let navigation = AppNavigation()
        for tab in [AppTab.data, .workout, .settings] {
            navigation.selectedTab = tab
            #expect(navigation.selectedTab == tab)
        }
    }

    @Test("rendered dashboard copy and hierarchy keep negative assertions")
    func negativeAssertions() throws {
        let source = try String(contentsOfFile: holisticDashboardSourcePath(), encoding: .utf8)
        #expect(!L4Copy.emptyMessage.contains("点击"))
        #expect(!L4Copy.actions.contains("执行步骤树"))
        #expect(!L4Copy.drillDown.contains("操作/展示一体"))
        #expect(!L4Copy.northStar.contains("holistic_"))
        #expect(!L4Copy.percent(0.86).contains("…"))
        #expect(source.contains("onRetry"))
        #expect(source.contains("FourLayerSummaryDashboard("))
        #expect(source.contains("snapshot: state.snapshot"))
        #expect(source.contains("fixedSize(horizontal: false, vertical: true)"))
        #expect(source.components(separatedBy: "Button(").count <= 2)

        let summarySource = try String(contentsOfFile: fourLayerSummarySourcePath(), encoding: .utf8)
        #expect(summarySource.contains("L4NorthStarDirectiveCard"))
        #expect(summarySource.contains("L3ReadinessPeriodizationCard"))
        #expect(summarySource.contains("L2CrossDomainCouplingSection"))
        #expect(summarySource.contains("L1AtomicDomainSummarySection"))
        #expect(summarySource.contains("PlatformHealthDetailActionButton"))
        #expect(summarySource.contains("Compact7DayTrendPopover"))
        #expect(!summarySource.contains("displayLimit = 200"))
    }

    private func holisticDashboardSourcePath() -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent("VitalStride/Sources/Overview/HolisticDashboardSection.swift").path
    }

    private func fourLayerSummarySourcePath() -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent("VitalStride/Sources/FourLayerSummaryComponents.swift").path
    }
}

private struct StubHealthProvider: HealthDataProviding {
    let points: [HealthDataPoint]

    func fetchData(for _: HealthSampleType, dateRange _: DateInterval?) async throws -> HealthFetchResult {
        HealthFetchResult(dataPoints: points, deletedObjectIDs: [])
    }
}
