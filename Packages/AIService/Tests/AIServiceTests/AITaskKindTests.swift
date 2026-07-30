import Foundation
import Testing
@testable import AIService

@Suite("AITaskKind Tests")
struct AITaskKindTests {

    @Test("AITaskKind is CaseIterable and covers all documented kinds")
    func caseIterableCoversDocumentedKinds() {
        // Spec FR-002: at least chat / overviewInsights / trainingAdvice / dataTrend / substitute.
        let expected: Set<AITaskKind> = [
            .chat, .overviewInsights, .trainingAdvice, .dataTrend, .substitute,
        ]
        let actual = Set(AITaskKind.allCases)
        #expect(expected.isSubset(of: actual), "AITaskKind must include the 5 documented kinds")
    }

    @Test("AITaskKind raw values are stable strings")
    func rawValuesAreStable() {
        // Raw values feed RoutingSignal persistence (US2) and grep-based invariants
        // (SC-002). They must be stable across releases.
        #expect(AITaskKind.chat.rawValue == "chat")
        #expect(AITaskKind.overviewInsights.rawValue == "overviewInsights")
        #expect(AITaskKind.trainingAdvice.rawValue == "trainingAdvice")
        #expect(AITaskKind.dataTrend.rawValue == "dataTrend")
        #expect(AITaskKind.substitute.rawValue == "substitute")
    }

    @Test("TaskRequirements has value semantics")
    func taskRequirementsValueSemantics() {
        let a = TaskRequirements(latency: .interactive, quality: .high, structured: true, carriesHealthData: true)
        let b = TaskRequirements(latency: .interactive, quality: .high, structured: true, carriesHealthData: true)
        let c = TaskRequirements(latency: .background, quality: .high, structured: true, carriesHealthData: true)

        #expect(a == b)
        #expect(a != c)
    }

    @Test("TaskRequirements fields are preserved")
    func taskRequirementsFieldsPreserved() {
        let requirements = TaskRequirements(
            latency: .background,
            quality: .low,
            structured: false,
            carriesHealthData: false
        )
        #expect(requirements.latency == .background)
        #expect(requirements.quality == .low)
        #expect(requirements.structured == false)
        #expect(requirements.carriesHealthData == false)
    }

    @Test("DeviceTier is CaseIterable and covers both tiers")
    func deviceTierCovered() {
        let all = Set(DeviceTier.allCases)
        #expect(all == [.appleIntelligenceCapable, .cloudOnly])
    }

    @Test("LatencyClass / QualityClass raw values are stable")
    func latencyAndQualityRawsStable() {
        #expect(LatencyClass.interactive.rawValue == "interactive")
        #expect(LatencyClass.background.rawValue == "background")
        #expect(QualityClass.low.rawValue == "low")
        #expect(QualityClass.medium.rawValue == "medium")
        #expect(QualityClass.high.rawValue == "high")
    }
}
