import Foundation
import HealthKitService
import os
import SwiftData
import VitalModels

enum UserInterestTracker {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.leepepe.VitalStride",
        category: "UserInterestTracker"
    )

    private static let defaultInterests: [HealthSampleType] = [
        .bodyMass, .heartRate, .sleepAnalysis,
    ]

    static func recordTap(for sampleType: HealthSampleType, in context: ModelContext) {
        let rawValue = sampleType.rawValue
        logger.debug("Recording tap for \(rawValue)")

        do {
            var descriptor = FetchDescriptor<UserInterest>(
                predicate: #Predicate { $0.sampleType == rawValue }
            )
            descriptor.fetchLimit = 1

            let existing = try context.fetch(descriptor)

            if let record = existing.first {
                record.tapCount += 1
                record.lastTappedDate = Date()
            } else {
                let record = UserInterest(sampleType: rawValue)
                context.insert(record)
            }
            try context.save()
        } catch {
            logger.error("Failed to record tap for \(rawValue): \(error.localizedDescription)")
        }
    }

    static func topInterests(limit: Int, in context: ModelContext) -> [HealthSampleType] {
        do {
            var descriptor = FetchDescriptor<UserInterest>(
                sortBy: [SortDescriptor(\.tapCount, order: .reverse)]
            )
            descriptor.fetchLimit = limit

            let results = try context.fetch(descriptor)

            if results.isEmpty {
                return Array(defaultInterests.prefix(limit))
            }

            return results.compactMap { HealthSampleType(rawValue: $0.sampleType) }
        } catch {
            logger.error("Failed to fetch top interests: \(error.localizedDescription)")
            return Array(defaultInterests.prefix(limit))
        }
    }
}
