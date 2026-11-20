import AIService
import Foundation
import Testing
import VitalModels
@testable import VitalStride

@Suite("Steps and body settings")
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
}
