import Foundation
import CryptoKit
import Testing
@testable import VitalModels

// Both modules decode AND encode these independently authored synthetic bytes.
// Load source fixtures without generating a test Bundle.module that would shadow
// VitalModels' production localization bundle in existing @testable tests.
@Suite("Physiological JSON wire contract")
struct PhysiologicalWireContractTests {
    @Test(arguments: ["full-snapshot", "missing-snapshot", "steps-snapshot", "reports", "strength"])
    func canonicalBytes(_ name: String) throws {
        let data = try wireFixture(name)
        let digests = [
            "full-snapshot": "e6583de43839c96488499c0eb84422cc14af4d091646747b7874c471fe76b627",
            "missing-snapshot": "9fa0a5197e0ba97dff06a13c5879429eaec14c74a4b027e10deb97faa7e09c53",
            "steps-snapshot": "a9b7c8c3b9a0cf48d767f77dc1da48e61535992ea70703cfb6f0cb9532ca12fd",
            "reports": "52e1202c996746aed88a6803527de3b3240f52efb20b90fdaf374bf00a4e88b0",
            "strength": "57f0b16f5f57bb8bd404778a2477d5e27a90b62102a03dfb1540f84b0967c7c5",
        ]
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == digests[name])
        let encoded: Data
        let encoder = JSONEncoder()
        switch name {
        case "reports":
            let reports = try JSONDecoder().decode([HolisticFourLayerReport].self, from: data)
            #expect(reports.map(\.l3.mesocyclePhase) == [.accumulation, .intensification, .realization, .deload])
            #expect(Set(reports.flatMap { $0.l1.map(\.severity) }) == Set(InsightSeverity.allCases))
            #expect(Set(reports.flatMap { $0.l1.map(\.domain) }) == Set(InsightDomain.allCases))
            #expect(reports.first?.l3.sleepRestorationScore == 65)
            encoded = try encoder.encode(reports)
        case "strength":
            let strength = try JSONDecoder().decode(StrengthWorkoutSummaryInput.self, from: data)
            #expect(strength.setCount == 16 && strength.healthKitUUID == "synthetic-workout")
            encoded = try encoder.encode(strength)
        default:
            let snapshot = try JSONDecoder().decode(PhysiologicalSnapshot.self, from: data)
            if name == "full-snapshot" {
                #expect(snapshot.heart.restingHeartRate.deltaFromBaselineBPM == 4)
                #expect(snapshot.heart.hrvCorridor.currentMilliseconds == 55)
                #expect(snapshot.heart.zoneDistribution.zone5Duration == 60)
                #expect(snapshot.sleep.recentNights.count == 1)
                #expect(snapshot.sleep.debt.missingNightCount7d == 1)
                #expect(snapshot.neat.hourlyNonWorkoutDistribution[17] == 900)
                #expect(snapshot.trainingLoad.recentTrajectory.last?.dailyLoad == 60)
                #expect(snapshot.availableDomains == Set(InsightDomain.allCases))
            } else {
                #expect(snapshot.availableDomains == (name == "steps-snapshot" ? [.neat] : []))
                #expect(!snapshot.sleep.isAvailable && !snapshot.trainingLoad.isAvailable)
            }
            encoded = try encoder.encode(snapshot)
        }
        #expect(try canonicalWireBytes(encoded) == data)
    }

    @Test("Legacy omitted optional/default fields expand without wire drift")
    func legacyDefaults() throws {
        var object = try #require(JSONSerialization.jsonObject(with: wireFixture("full-snapshot")) as? [String: Any])
        object.removeValue(forKey: "availableDomains")
        var heart = try #require(object["heart"] as? [String: Any])
        var rhr = try #require(heart["restingHeartRate"] as? [String: Any])
        for key in ["currentBPM", "sevenDayAverageBPM", "baselineBPM", "baselineDayCount"] { rhr.removeValue(forKey: key) }
        heart["restingHeartRate"] = rhr
        var hrv = try #require(heart["hrvCorridor"] as? [String: Any])
        for key in ["currentMilliseconds", "sevenDayAverageMilliseconds", "sevenDaySampleCount", "baselineDayCount"] { hrv.removeValue(forKey: key) }
        heart["hrvCorridor"] = hrv
        object["heart"] = heart
        var neat = try #require(object["neat"] as? [String: Any])
        for key in ["nonWorkoutSteps", "workoutActiveEnergyExcluded", "standDuration", "activeNonWorkoutHourCount", "hourlyNonWorkoutDistribution"] { neat.removeValue(forKey: key) }
        object["neat"] = neat
        var sleep = try #require(object["sleep"] as? [String: Any])
        sleep.removeValue(forKey: "recentNights")
        object["sleep"] = sleep
        var load = try #require(object["trainingLoad"] as? [String: Any])
        for key in ["atlDelta7d", "ctlDelta7d", "ctlDelta14d", "tsbDelta7d", "deduplicatedWorkoutCount", "recentTrajectory"] {
            load.removeValue(forKey: key)
        }
        object["trainingLoad"] = load
        let decoded = try JSONDecoder().decode(PhysiologicalSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.availableDomains == Set(InsightDomain.allCases))
        #expect(decoded.heart.restingHeartRate.currentBPM == 60 && decoded.heart.restingHeartRate.baselineDayCount == 0)
        #expect(decoded.heart.hrvCorridor.currentMilliseconds == 60 && decoded.heart.hrvCorridor.sevenDaySampleCount == 0)
        #expect(decoded.neat.nonWorkoutSteps == 8000 && decoded.neat.standDuration == 0 && decoded.neat.hourlyNonWorkoutDistribution.isEmpty)
        #expect(decoded.sleep.recentNights.isEmpty)
        #expect(decoded.trainingLoad.ctlDelta14d == 0 && decoded.trainingLoad.recentTrajectory.isEmpty)
        #expect(decoded.trainingLoad.acuteTrainingLoad == 55)
        #expect(try JSONDecoder().decode(PhysiologicalSnapshot.self, from: JSONEncoder().encode(decoded)) == decoded)

        var reports = try #require(JSONSerialization.jsonObject(with: wireFixture("reports")) as? [[String: Any]])
        var l3 = try #require(reports[0]["l3"] as? [String: Any])
        for key in ["autonomicScore", "sleepRestorationScore", "fatigueBalanceScore", "contributingInsights"] {
            l3.removeValue(forKey: key)
        }
        reports[0]["l3"] = l3
        let legacy = try JSONDecoder().decode([HolisticFourLayerReport].self, from: JSONSerialization.data(withJSONObject: reports))
        #expect(legacy[0].l3.autonomicScore == 0 && legacy[0].l3.contributingInsights.isEmpty)
        #expect(legacy[0].l4.prioritizedActions.count == 2)
    }
}

func wireFixture(_ name: String) throws -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures").appendingPathComponent(name + ".json")
    return try Data(contentsOf: url)
}

private func canonicalWireBytes(_ data: Data) throws -> Data {
    func normalize(_ value: Any) -> Any {
        if let values = value as? [Any] { return values.map(normalize) }
        guard var object = value as? [String: Any] else { return value }
        object = object.mapValues(normalize)
        if let domains = object["availableDomains"] as? [String] { object["availableDomains"] = domains.sorted() }
        // Swift encodes non-String/Int dictionary keys as alternating arrays.
        if let zones = object["durationsByZone"] as? [Any] {
            let pairs = stride(from: 0, to: zones.count, by: 2).map { index in
                (zones[index] as? String ?? "", zones[index + 1])
            }.sorted { $0.0 < $1.0 }
            object["durationsByZone"] = pairs.flatMap { [$0.0, $0.1] as [Any] }
        }
        return object
    }
    return try JSONSerialization.data(withJSONObject: normalize(JSONSerialization.jsonObject(with: data)), options: [.sortedKeys, .withoutEscapingSlashes])
}
