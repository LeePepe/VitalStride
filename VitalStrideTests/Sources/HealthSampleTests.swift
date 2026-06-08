import Foundation
import Testing

@testable import HealthKitService

@Suite("HealthKitAnchorStore Tests")
struct HealthKitAnchorStoreTests {
    let store: HealthKitAnchorStore

    init() {
        let defaults = UserDefaults(suiteName: "HealthKitAnchorStoreTests_\(UUID().uuidString)")!
        store = HealthKitAnchorStore(defaults: defaults, keyPrefix: "test_anchor")
    }

    @Test("Store and retrieve anchor for a sample type")
    func storeAndRetrieve() {
        let anchorData = Data([0x01, 0x02, 0x03])
        let syncDate = Date()
        let record = AnchorRecord(anchorData: anchorData, lastSyncDate: syncDate)

        store.setAnchor(record, for: .heartRate, deviceIdentifier: "device-1")

        let retrieved = store.anchor(for: .heartRate, deviceIdentifier: "device-1")
        #expect(retrieved != nil)
        #expect(retrieved?.anchorData == anchorData)
    }

    @Test("Returns nil for missing anchor")
    func missingAnchor() {
        let result = store.anchor(for: .stepCount, deviceIdentifier: "device-1")
        #expect(result == nil)
    }

    @Test("Different sample types stored independently")
    func distinctSampleTypes() {
        let record1 = AnchorRecord(anchorData: Data([0x01]), lastSyncDate: Date())
        let record2 = AnchorRecord(anchorData: Data([0x02]), lastSyncDate: Date())

        store.setAnchor(record1, for: .heartRate, deviceIdentifier: "device-1")
        store.setAnchor(record2, for: .stepCount, deviceIdentifier: "device-1")

        let r1 = store.anchor(for: .heartRate, deviceIdentifier: "device-1")
        let r2 = store.anchor(for: .stepCount, deviceIdentifier: "device-1")
        #expect(r1?.anchorData == Data([0x01]))
        #expect(r2?.anchorData == Data([0x02]))
    }

    @Test("Per-device isolation")
    func perDeviceIsolation() {
        let record1 = AnchorRecord(anchorData: Data([0xAA]), lastSyncDate: Date())
        let record2 = AnchorRecord(anchorData: Data([0xBB]), lastSyncDate: Date())

        store.setAnchor(record1, for: .heartRate, deviceIdentifier: "iphone-15")
        store.setAnchor(record2, for: .heartRate, deviceIdentifier: "apple-watch-9")

        let r1 = store.anchor(for: .heartRate, deviceIdentifier: "iphone-15")
        let r2 = store.anchor(for: .heartRate, deviceIdentifier: "apple-watch-9")
        #expect(r1?.anchorData == Data([0xAA]))
        #expect(r2?.anchorData == Data([0xBB]))
    }

    @Test("Update existing anchor overwrites")
    func updateAnchor() {
        let original = AnchorRecord(anchorData: Data([0x01]), lastSyncDate: Date())
        store.setAnchor(original, for: .bodyMass, deviceIdentifier: "device-1")

        let updated = AnchorRecord(anchorData: Data([0xFF]), lastSyncDate: Date())
        store.setAnchor(updated, for: .bodyMass, deviceIdentifier: "device-1")

        let result = store.anchor(for: .bodyMass, deviceIdentifier: "device-1")
        #expect(result?.anchorData == Data([0xFF]))
    }

    @Test("Remove anchor")
    func removeAnchor() {
        let record = AnchorRecord(anchorData: Data([0x01]), lastSyncDate: Date())
        store.setAnchor(record, for: .heartRate, deviceIdentifier: "device-1")
        store.removeAnchor(for: .heartRate, deviceIdentifier: "device-1")

        let result = store.anchor(for: .heartRate, deviceIdentifier: "device-1")
        #expect(result == nil)
    }

    @Test("Remove all anchors for a device")
    func removeAllAnchorsForDevice() {
        for sampleType in HealthSampleType.allCases {
            let record = AnchorRecord(anchorData: Data([0x01]), lastSyncDate: Date())
            store.setAnchor(record, for: sampleType, deviceIdentifier: "device-1")
        }

        store.removeAllAnchors(for: "device-1")

        for sampleType in HealthSampleType.allCases {
            #expect(store.anchor(for: sampleType, deviceIdentifier: "device-1") == nil)
        }
    }

    @Test("All sample types can store anchors")
    func allSampleTypes() {
        for sampleType in HealthSampleType.allCases {
            let record = AnchorRecord(anchorData: Data([0x01]), lastSyncDate: Date())
            store.setAnchor(record, for: sampleType, deviceIdentifier: "device-1")
        }

        for sampleType in HealthSampleType.allCases {
            let result = store.anchor(for: sampleType, deviceIdentifier: "device-1")
            #expect(result != nil)
        }
    }
}

@Suite("HealthSampleType Enum Tests")
struct HealthSampleTypeTests {
    @Test("HealthSampleType has all expected cases")
    func healthSampleTypeCases() {
        let cases = HealthSampleType.allCases
        #expect(cases.count == 23)
        #expect(cases.contains(.heartRate))
        #expect(cases.contains(.stepCount))
        #expect(cases.contains(.bodyMass))
        #expect(cases.contains(.sleepAnalysis))
        #expect(cases.contains(.activeEnergyBurned))
        #expect(cases.contains(.basalEnergyBurned))
        #expect(cases.contains(.distanceWalkingRunning))
        #expect(cases.contains(.distanceCycling))
        #expect(cases.contains(.appleExerciseTime))
        #expect(cases.contains(.appleStandTime))
        #expect(cases.contains(.flightsClimbed))
        #expect(cases.contains(.bodyFatPercentage))
        #expect(cases.contains(.leanBodyMass))
        #expect(cases.contains(.height))
        #expect(cases.contains(.bodyMassIndex))
        #expect(cases.contains(.restingHeartRate))
        #expect(cases.contains(.heartRateVariabilitySDNN))
        #expect(cases.contains(.vo2Max))
        #expect(cases.contains(.dietaryEnergyConsumed))
        #expect(cases.contains(.dietaryProtein))
        #expect(cases.contains(.dietaryCarbohydrates))
        #expect(cases.contains(.dietaryFatTotal))
        #expect(cases.contains(.dietaryWater))
    }

    @Test("HealthSampleType raw values match expected strings")
    func healthSampleTypeRawValues() {
        #expect(HealthSampleType.heartRate.rawValue == "heartRate")
        #expect(HealthSampleType.stepCount.rawValue == "stepCount")
        #expect(HealthSampleType.bodyMass.rawValue == "bodyMass")
        #expect(HealthSampleType.sleepAnalysis.rawValue == "sleepAnalysis")
        #expect(HealthSampleType.activeEnergyBurned.rawValue == "activeEnergyBurned")
    }

    @Test("HealthSampleType is Codable")
    func healthSampleTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for sampleType in HealthSampleType.allCases {
            let data = try encoder.encode(sampleType)
            let decoded = try decoder.decode(HealthSampleType.self, from: data)
            #expect(decoded == sampleType)
        }
    }
}
