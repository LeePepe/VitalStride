import Testing
import Foundation
@testable import HealthKitService

@Suite("HealthWorkoutRecord")
struct HealthWorkoutRecordTests {

    // MARK: - Construction

    @Test("Init stores all fields correctly")
    func initStoresFields() {
        let id = UUID()
        let start = Date()
        let end = start.addingTimeInterval(3600)

        let record = HealthWorkoutRecord(
            id: id,
            activityTypeRawValue: 37,
            duration: 3600,
            totalEnergyBurned: 500.0,
            totalDistance: 10_000.0,
            startDate: start,
            endDate: end,
            sourceName: "Apple Watch"
        )

        #expect(record.id == id)
        #expect(record.activityTypeRawValue == 37)
        #expect(record.duration == 3600)
        #expect(record.totalEnergyBurned == 500.0)
        #expect(record.totalDistance == 10_000.0)
        #expect(record.startDate == start)
        #expect(record.endDate == end)
        #expect(record.sourceName == "Apple Watch")
    }

    @Test("Optional fields can be nil")
    func optionalFieldsNil() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: 13,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            sourceName: nil
        )

        #expect(record.totalEnergyBurned == nil)
        #expect(record.totalDistance == nil)
        #expect(record.sourceName == nil)
    }

    // MARK: - ActivityType Mapping

    @Test("Known rawValue maps to correct WorkoutActivityType")
    func knownActivityTypeMapping() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: 37,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date(),
            sourceName: nil
        )

        #expect(record.activityType == .running)
    }

    @Test("Unknown rawValue maps to .other")
    func unknownActivityTypeMapping() {
        let record = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: 9999,
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(),
            endDate: Date(),
            sourceName: nil
        )

        #expect(record.activityType == .other)
    }

    @Test("All WorkoutActivityType cases have correct rawValues")
    func allActivityTypeCases() {
        #expect(WorkoutActivityType.cycling.rawValue == 13)
        #expect(WorkoutActivityType.dance.rawValue == 14)
        #expect(WorkoutActivityType.elliptical.rawValue == 16)
        #expect(WorkoutActivityType.functionalStrengthTraining.rawValue == 20)
        #expect(WorkoutActivityType.hiking.rawValue == 24)
        #expect(WorkoutActivityType.rowing.rawValue == 35)
        #expect(WorkoutActivityType.running.rawValue == 37)
        #expect(WorkoutActivityType.swimming.rawValue == 46)
        #expect(WorkoutActivityType.traditionalStrengthTraining.rawValue == 50)
        #expect(WorkoutActivityType.walking.rawValue == 52)
        #expect(WorkoutActivityType.yoga.rawValue == 54)
        #expect(WorkoutActivityType.highIntensityIntervalTraining.rawValue == 63)
    }

    // MARK: - Codable

    @Test("Codable roundtrip preserves all fields")
    func codableRoundtrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        let original = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: 37,
            duration: 3600,
            totalEnergyBurned: 450.5,
            totalDistance: 5000.0,
            startDate: start,
            endDate: end,
            sourceName: "Strava"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthWorkoutRecord.self, from: data)

        #expect(decoded == original)
    }

    @Test("Codable roundtrip with nil optionals")
    func codableRoundtripNilOptionals() throws {
        let original = HealthWorkoutRecord(
            id: UUID(),
            activityTypeRawValue: 50,
            duration: 2700,
            totalEnergyBurned: nil,
            totalDistance: nil,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_002_700),
            sourceName: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HealthWorkoutRecord.self, from: data)

        #expect(decoded == original)
    }

    @Test("Array codable roundtrip")
    func arrayCodableRoundtrip() throws {
        let baseTime: TimeInterval = 1_700_000_000
        let records: [HealthWorkoutRecord] = (0..<5).map { i in
            let offset = Double(i) * 86400
            let start = Date(timeIntervalSince1970: baseTime + offset)
            let end = Date(timeIntervalSince1970: baseTime + 1800 + offset)
            return HealthWorkoutRecord(
                id: UUID(),
                activityTypeRawValue: UInt(37 + i),
                duration: Double(1800 + i * 300),
                totalEnergyBurned: Double(200 + i * 50),
                totalDistance: Double(3000 + i * 1000),
                startDate: start,
                endDate: end,
                sourceName: "Source \(i)"
            )
        }

        let data = try JSONEncoder().encode(records)
        let decoded = try JSONDecoder().decode([HealthWorkoutRecord].self, from: data)

        #expect(decoded.count == 5)
        for (original, restored) in zip(records, decoded) {
            #expect(original == restored)
        }
    }

    // MARK: - WorkoutFetchResult

    @Test("WorkoutFetchResult stores workouts and deleted IDs")
    func fetchResultStoresFields() {
        let workouts = [
            HealthWorkoutRecord(
                id: UUID(),
                activityTypeRawValue: 37,
                duration: 3600,
                totalEnergyBurned: 500,
                totalDistance: 10_000,
                startDate: Date(),
                endDate: Date(),
                sourceName: nil
            ),
        ]
        let deletedIDs = [UUID(), UUID()]

        let result = WorkoutFetchResult(workouts: workouts, deletedObjectIDs: deletedIDs)

        #expect(result.workouts.count == 1)
        #expect(result.deletedObjectIDs.count == 2)
    }
}
