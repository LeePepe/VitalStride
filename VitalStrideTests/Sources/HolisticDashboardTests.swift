import AIService
import Testing
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
}
