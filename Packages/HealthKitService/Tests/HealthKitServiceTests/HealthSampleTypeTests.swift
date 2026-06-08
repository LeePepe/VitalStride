import Foundation
import HealthKit
import Testing
@testable import HealthKitService

@Suite("HealthSampleType")
struct HealthSampleTypeTests {

    @Test("allCases contains 23 types (5 original + 18 new)")
    func allCasesCount() {
        #expect(HealthSampleType.allCases.count == 23)
    }

    // MARK: - hkSampleType

    @Test("hkSampleType maps quantity types to HKQuantityType", arguments: [
        (HealthSampleType.heartRate, HKQuantityTypeIdentifier.heartRate),
        (.stepCount, .stepCount),
        (.bodyMass, .bodyMass),
        (.activeEnergyBurned, .activeEnergyBurned),
        (.basalEnergyBurned, .basalEnergyBurned),
        (.distanceWalkingRunning, .distanceWalkingRunning),
        (.distanceCycling, .distanceCycling),
        (.appleExerciseTime, .appleExerciseTime),
        (.appleStandTime, .appleStandTime),
        (.flightsClimbed, .flightsClimbed),
        (.bodyFatPercentage, .bodyFatPercentage),
        (.leanBodyMass, .leanBodyMass),
        (.height, .height),
        (.bodyMassIndex, .bodyMassIndex),
        (.restingHeartRate, .restingHeartRate),
        (.heartRateVariabilitySDNN, .heartRateVariabilitySDNN),
        (.vo2Max, .vo2Max),
        (.dietaryEnergyConsumed, .dietaryEnergyConsumed),
        (.dietaryProtein, .dietaryProtein),
        (.dietaryCarbohydrates, .dietaryCarbohydrates),
        (.dietaryFatTotal, .dietaryFatTotal),
        (.dietaryWater, .dietaryWater),
    ])
    func quantityTypeMappings(sampleType: HealthSampleType, expected: HKQuantityTypeIdentifier) {
        #expect(sampleType.hkSampleType == HKQuantityType(expected))
    }

    @Test("sleepAnalysis maps to HKCategoryType")
    func sleepAnalysisMapsToCategory() {
        #expect(HealthSampleType.sleepAnalysis.hkSampleType == HKCategoryType(.sleepAnalysis))
    }

    // MARK: - hkUnit

    @Test("hkUnit mappings are correct", arguments: [
        (HealthSampleType.heartRate, HKUnit.count().unitDivided(by: .minute())),
        (.stepCount, HKUnit.count()),
        (.bodyMass, HKUnit.gramUnit(with: .kilo)),
        (.activeEnergyBurned, HKUnit.kilocalorie()),
        (.sleepAnalysis, HKUnit.count()),
        (.basalEnergyBurned, HKUnit.kilocalorie()),
        (.distanceWalkingRunning, HKUnit.meter()),
        (.distanceCycling, HKUnit.meter()),
        (.appleExerciseTime, HKUnit.minute()),
        (.appleStandTime, HKUnit.minute()),
        (.flightsClimbed, HKUnit.count()),
        (.bodyFatPercentage, HKUnit.percent()),
        (.leanBodyMass, HKUnit.gramUnit(with: .kilo)),
        (.height, HKUnit.meter()),
        (.bodyMassIndex, HKUnit.count()),
        (.restingHeartRate, HKUnit.count().unitDivided(by: .minute())),
        (.heartRateVariabilitySDNN, HKUnit.secondUnit(with: .milli)),
        (.vo2Max, HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))),
        (.dietaryEnergyConsumed, HKUnit.kilocalorie()),
        (.dietaryProtein, HKUnit.gram()),
        (.dietaryCarbohydrates, HKUnit.gram()),
        (.dietaryFatTotal, HKUnit.gram()),
        (.dietaryWater, HKUnit.literUnit(with: .milli)),
    ])
    func unitMappings(sampleType: HealthSampleType, expected: HKUnit) {
        #expect(sampleType.hkUnit == expected)
    }

    // MARK: - unitString

    @Test("unitString mappings are correct", arguments: [
        (HealthSampleType.heartRate, "bpm"),
        (.stepCount, "count"),
        (.bodyMass, "kg"),
        (.activeEnergyBurned, "kcal"),
        (.sleepAnalysis, "category"),
        (.basalEnergyBurned, "kcal"),
        (.distanceWalkingRunning, "m"),
        (.distanceCycling, "m"),
        (.appleExerciseTime, "min"),
        (.appleStandTime, "min"),
        (.flightsClimbed, "count"),
        (.bodyFatPercentage, "%"),
        (.leanBodyMass, "kg"),
        (.height, "m"),
        (.bodyMassIndex, "count"),
        (.restingHeartRate, "bpm"),
        (.heartRateVariabilitySDNN, "ms"),
        (.vo2Max, "mL/kg\u{00B7}min"),
        (.dietaryEnergyConsumed, "kcal"),
        (.dietaryProtein, "g"),
        (.dietaryCarbohydrates, "g"),
        (.dietaryFatTotal, "g"),
        (.dietaryWater, "mL"),
    ])
    func unitStringMappings(sampleType: HealthSampleType, expected: String) {
        #expect(sampleType.unitString == expected)
    }

    // MARK: - readTypes

    @Test("readTypes contains all HealthSampleType cases")
    func readTypesMatchesAllCases() {
        let readTypes = HealthKitService.readTypes
        let expectedCount = HealthSampleType.allCases.count + 1 // +1 for HKWorkoutType
        #expect(readTypes.count == expectedCount)

        for sampleType in HealthSampleType.allCases {
            let hkType = sampleType.hkSampleType as HKObjectType
            #expect(readTypes.contains(hkType), "readTypes missing \(sampleType.rawValue)")
        }
        #expect(readTypes.contains(HKWorkoutType.workoutType()))
    }

    // MARK: - Codable roundtrip

    @Test("All new HealthSampleType cases roundtrip through JSON")
    func codableRoundtrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for sampleType in HealthSampleType.allCases {
            let data = try encoder.encode(sampleType)
            let decoded = try decoder.decode(HealthSampleType.self, from: data)
            #expect(decoded == sampleType)
        }
    }
}
