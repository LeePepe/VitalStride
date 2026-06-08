import Foundation
import Testing
@testable import HealthKitService

@Suite("HealthDataPoint Codable")
struct HealthDataPointCodableTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Test("Roundtrip preserves all fields")
    func roundtrip() throws {
        let point = HealthDataPoint(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            sampleType: .heartRate,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_060),
            value: 72.0,
            unit: "count/min",
            sleepStage: nil,
            sourceName: "Apple Watch"
        )

        let data = try encoder.encode(point)
        let decoded = try decoder.decode(HealthDataPoint.self, from: data)

        #expect(decoded.id == point.id)
        #expect(decoded.sampleType == point.sampleType)
        #expect(decoded.startDate == point.startDate)
        #expect(decoded.endDate == point.endDate)
        #expect(decoded.value == point.value)
        #expect(decoded.unit == point.unit)
        #expect(decoded.sleepStage == nil)
        #expect(decoded.sourceName == point.sourceName)
    }

    @Test("Roundtrip with sleepStage")
    func roundtripWithSleepStage() throws {
        let point = HealthDataPoint(
            id: UUID(),
            sampleType: .sleepAnalysis,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_028_800),
            value: 1.0,
            unit: "",
            sleepStage: .asleepDeep,
            sourceName: nil
        )

        let data = try encoder.encode(point)
        let decoded = try decoder.decode(HealthDataPoint.self, from: data)

        #expect(decoded.sleepStage == .asleepDeep)
        #expect(decoded.sourceName == nil)
    }

    @Test("Array roundtrip")
    func arrayRoundtrip() throws {
        let points = [
            HealthDataPoint(
                id: UUID(),
                sampleType: .stepCount,
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600),
                value: 5000,
                unit: "count",
                sleepStage: nil,
                sourceName: "iPhone"
            ),
            HealthDataPoint(
                id: UUID(),
                sampleType: .bodyMass,
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_000_000),
                value: 75.5,
                unit: "kg",
                sleepStage: nil,
                sourceName: nil
            ),
            HealthDataPoint(
                id: UUID(),
                sampleType: .sleepAnalysis,
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_028_800),
                value: 1.0,
                unit: "",
                sleepStage: .asleepREM,
                sourceName: "Apple Watch"
            ),
        ]

        let data = try encoder.encode(points)
        let decoded = try decoder.decode([HealthDataPoint].self, from: data)

        #expect(decoded.count == 3)
        for (original, result) in zip(points, decoded) {
            #expect(result.id == original.id)
            #expect(result.sampleType == original.sampleType)
            #expect(result.value == original.value)
            #expect(result.sleepStage == original.sleepStage)
        }
    }

    @Test("All SleepStage values roundtrip correctly")
    func allSleepStages() throws {
        for stage in SleepStage.allCases {
            let point = HealthDataPoint(
                id: UUID(),
                sampleType: .sleepAnalysis,
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_028_800),
                value: 1.0,
                unit: "",
                sleepStage: stage,
                sourceName: nil
            )

            let data = try encoder.encode(point)
            let decoded = try decoder.decode(HealthDataPoint.self, from: data)
            #expect(decoded.sleepStage == stage)
        }
    }
}
