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

    // MARK: - Schema Pinning

    @Test("Encoded JSON contains expected keys")
    func encodedSchemaKeys() throws {
        let point = HealthDataPoint(
            id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
            sampleType: .heartRate,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_060),
            value: 72.0,
            unit: "count/min",
            sleepStage: .asleepDeep,
            sourceName: "Apple Watch"
        )

        let data = try encoder.encode(point)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let keys = Set(json.keys)

        let expectedKeys: Set<String> = [
            "id", "sampleType", "startDate", "endDate",
            "value", "unit", "sleepStage", "sourceName",
        ]
        #expect(keys == expectedKeys)
    }

    @Test("Encoded sampleType uses rawValue string")
    func sampleTypeEncodesAsRawValue() throws {
        let point = HealthDataPoint(
            id: UUID(),
            sampleType: .stepCount,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 0),
            value: 100,
            unit: "count",
            sleepStage: nil,
            sourceName: nil
        )

        let data = try encoder.encode(point)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["sampleType"] as? String == "stepCount")
    }

    @Test("Encoded sleepStage uses rawValue string")
    func sleepStageEncodesAsRawValue() throws {
        let point = HealthDataPoint(
            id: UUID(),
            sampleType: .sleepAnalysis,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 0),
            value: 1.0,
            unit: "",
            sleepStage: .asleepREM,
            sourceName: nil
        )

        let data = try encoder.encode(point)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["sleepStage"] as? String == "asleepREM")
    }

    @Test("Null optionals survive roundtrip")
    func nullOptionalsRoundtrip() throws {
        let point = HealthDataPoint(
            id: UUID(),
            sampleType: .bodyMass,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_000),
            value: 80.0,
            unit: "kg",
            sleepStage: nil,
            sourceName: nil
        )

        let data = try encoder.encode(point)
        let decoded = try decoder.decode(HealthDataPoint.self, from: data)
        #expect(decoded.sleepStage == nil)
        #expect(decoded.sourceName == nil)
    }

    // MARK: - Malformed Data

    @Test("Decode fails for missing required field")
    func decodeMissingRequiredField() throws {
        let json = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "sampleType": "heartRate",
            "startDate": 1700000000,
            "value": 72.0,
            "unit": "count/min"
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(HealthDataPoint.self, from: json)
        }
    }

    @Test("Decode fails for invalid sampleType")
    func decodeInvalidSampleType() throws {
        let json = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "sampleType": "unknownType",
            "startDate": 1700000000,
            "endDate": 1700000060,
            "value": 72.0,
            "unit": "count/min",
            "sleepStage": null,
            "sourceName": null
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(HealthDataPoint.self, from: json)
        }
    }

    @Test("Decode fails for invalid sleepStage")
    func decodeInvalidSleepStage() throws {
        let json = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "sampleType": "sleepAnalysis",
            "startDate": 1700000000,
            "endDate": 1700028800,
            "value": 1.0,
            "unit": "",
            "sleepStage": "invalidStage",
            "sourceName": null
        }
        """.data(using: .utf8)!

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(HealthDataPoint.self, from: json)
        }
    }

    @Test("Decode fails for completely invalid JSON")
    func decodeGarbage() throws {
        let garbage = Data("not valid json".utf8)

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(HealthDataPoint.self, from: garbage)
        }
    }

    @Test("Decode fails for empty object")
    func decodeEmptyObject() throws {
        let json = Data("{}".utf8)

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(HealthDataPoint.self, from: json)
        }
    }

    @Test("All HealthSampleType cases roundtrip via Codable")
    func allSampleTypesRoundtrip() throws {
        for sampleType in HealthSampleType.allCases {
            let point = HealthDataPoint(
                id: UUID(),
                sampleType: sampleType,
                startDate: Date(timeIntervalSince1970: 1_700_000_000),
                endDate: Date(timeIntervalSince1970: 1_700_003_600),
                value: 42.0,
                unit: "unit",
                sleepStage: nil,
                sourceName: nil
            )

            let data = try encoder.encode(point)
            let decoded = try decoder.decode(HealthDataPoint.self, from: data)
            #expect(decoded.sampleType == sampleType)
        }
    }
}
