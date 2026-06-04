import Foundation
import SwiftData
import Testing

@testable import VitalStride

@Suite("HealthSample Model Tests")
struct HealthSampleTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("HealthSample creation with quantity type (heartRate)")
    func healthSampleQuantityCreation() throws {
        let context = ModelContext(container)
        let start = Date()
        let end = start.addingTimeInterval(60)
        let sample = HealthSample(
            sampleType: .heartRate,
            value: 72.0,
            unit: "count/min",
            startDate: start,
            endDate: end,
            sourceDevice: "Apple Watch Series 9"
        )
        context.insert(sample)
        try context.save()

        #expect(sample.sampleType == .heartRate)
        #expect(sample.value == 72.0)
        #expect(sample.unit == "count/min")
        #expect(sample.startDate == start)
        #expect(sample.endDate == end)
        #expect(sample.sourceDevice == "Apple Watch Series 9")
    }

    @Test("HealthSample creation with stepCount")
    func healthSampleStepCount() throws {
        let context = ModelContext(container)
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let sample = HealthSample(
            sampleType: .stepCount,
            value: 1500.0,
            unit: "count",
            startDate: start,
            endDate: end
        )
        context.insert(sample)
        try context.save()

        #expect(sample.sampleType == .stepCount)
        #expect(sample.value == 1500.0)
        #expect(sample.unit == "count")
        #expect(sample.sourceDevice == nil)
    }

    @Test("HealthSample creation with bodyMass")
    func healthSampleBodyMass() throws {
        let context = ModelContext(container)
        let now = Date()
        let sample = HealthSample(
            sampleType: .bodyMass,
            value: 75.5,
            unit: "kg",
            startDate: now,
            endDate: now
        )
        context.insert(sample)
        try context.save()

        #expect(sample.sampleType == .bodyMass)
        #expect(sample.value == 75.5)
        #expect(sample.unit == "kg")
    }

    @Test("HealthSample creation with sleepAnalysis (category type)")
    func healthSampleSleepAnalysis() throws {
        let context = ModelContext(container)
        let start = Date()
        let end = start.addingTimeInterval(28800)
        let sample = HealthSample(
            sampleType: .sleepAnalysis,
            value: 1.0,
            startDate: start,
            endDate: end
        )
        context.insert(sample)
        try context.save()

        #expect(sample.sampleType == .sleepAnalysis)
        #expect(sample.value == 1.0)
        #expect(sample.unit == nil)
    }

    @Test("HealthSample creation with activeEnergyBurned")
    func healthSampleActiveEnergy() throws {
        let context = ModelContext(container)
        let start = Date()
        let end = start.addingTimeInterval(1800)
        let sample = HealthSample(
            sampleType: .activeEnergyBurned,
            value: 350.0,
            unit: "kcal",
            startDate: start,
            endDate: end,
            sourceDevice: "iPhone 15 Pro"
        )
        context.insert(sample)
        try context.save()

        #expect(sample.sampleType == .activeEnergyBurned)
        #expect(sample.value == 350.0)
        #expect(sample.unit == "kcal")
        #expect(sample.sourceDevice == "iPhone 15 Pro")
    }

    @Test("HealthSample CRUD - fetch after insert")
    func healthSampleFetch() throws {
        let context = ModelContext(container)
        let now = Date()
        let sample = HealthSample(
            sampleType: .heartRate,
            value: 85.0,
            unit: "count/min",
            startDate: now,
            endDate: now
        )
        context.insert(sample)
        try context.save()

        let descriptor = FetchDescriptor<HealthSample>()
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.value == 85.0)
    }

    @Test("HealthSample unique ID")
    func healthSampleUniqueId() throws {
        let context = ModelContext(container)
        let now = Date()
        let sample1 = HealthSample(
            sampleType: .heartRate,
            value: 70.0,
            unit: "count/min",
            startDate: now,
            endDate: now
        )
        let sample2 = HealthSample(
            sampleType: .heartRate,
            value: 80.0,
            unit: "count/min",
            startDate: now,
            endDate: now
        )
        context.insert(sample1)
        context.insert(sample2)
        try context.save()

        #expect(sample1.id != sample2.id)
    }
}

@Suite("HealthKitAnchor Model Tests")
struct HealthKitAnchorTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("HealthKitAnchor creation and property assignment")
    func anchorCreation() throws {
        let context = ModelContext(container)
        let anchorData = Data([0x01, 0x02, 0x03, 0x04])
        let syncDate = Date()
        let anchor = HealthKitAnchor(
            sampleType: .heartRate,
            anchorData: anchorData,
            lastSyncDate: syncDate
        )
        context.insert(anchor)
        try context.save()

        #expect(anchor.sampleType == .heartRate)
        #expect(anchor.anchorData == anchorData)
        #expect(anchor.lastSyncDate == syncDate)
    }

    @Test("HealthKitAnchor fetch after insert")
    func anchorFetch() throws {
        let context = ModelContext(container)
        let anchorData = Data([0xAA, 0xBB])
        let anchor = HealthKitAnchor(
            sampleType: .stepCount,
            anchorData: anchorData
        )
        context.insert(anchor)
        try context.save()

        let descriptor = FetchDescriptor<HealthKitAnchor>()
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.sampleType == .stepCount)
    }

    @Test("HealthKitAnchor distinct sampleType per anchor")
    func anchorDistinctSampleTypes() throws {
        let context = ModelContext(container)
        let anchor1 = HealthKitAnchor(
            sampleType: .bodyMass,
            anchorData: Data([0x01])
        )
        let anchor2 = HealthKitAnchor(
            sampleType: .heartRate,
            anchorData: Data([0x02])
        )
        context.insert(anchor1)
        context.insert(anchor2)
        try context.save()

        let descriptor = FetchDescriptor<HealthKitAnchor>()
        let results = try context.fetch(descriptor)
        #expect(results.count == 2)
    }

    @Test("HealthKitAnchor for all sample types")
    func anchorAllSampleTypes() throws {
        let context = ModelContext(container)
        for sampleType in HealthSampleType.allCases {
            let anchor = HealthKitAnchor(
                sampleType: sampleType,
                anchorData: Data([0x00])
            )
            context.insert(anchor)
        }
        try context.save()

        let descriptor = FetchDescriptor<HealthKitAnchor>()
        let results = try context.fetch(descriptor)
        #expect(results.count == HealthSampleType.allCases.count)
    }
}

@Suite("HealthSampleType Enum Tests")
struct HealthSampleTypeTests {
    @Test("HealthSampleType has all expected cases")
    func healthSampleTypeCases() {
        let cases = HealthSampleType.allCases
        #expect(cases.count == 5)
        #expect(cases.contains(.heartRate))
        #expect(cases.contains(.stepCount))
        #expect(cases.contains(.bodyMass))
        #expect(cases.contains(.sleepAnalysis))
        #expect(cases.contains(.activeEnergyBurned))
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

@Suite("ModelContainer includes Health models")
struct HealthModelContainerTests {
    @Test("Container schema contains HealthSample and HealthKitAnchor")
    func containerIncludesHealthModels() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let entityNames = container.schema.entities.map(\.name)

        #expect(entityNames.contains("HealthSample"))
        #expect(entityNames.contains("HealthKitAnchor"))
    }

    @Test("Container entity count includes new models")
    func containerEntityCount() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        #expect(container.schema.entities.count == 8)
    }
}
