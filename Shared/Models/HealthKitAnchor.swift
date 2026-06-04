import Foundation
import SwiftData

@Model
final class HealthKitAnchor {
    var sampleType: HealthSampleType = HealthSampleType.heartRate
    var anchorData: Data = Data()
    var lastSyncDate: Date = Date()

    init(
        sampleType: HealthSampleType,
        anchorData: Data,
        lastSyncDate: Date = Date()
    ) {
        self.sampleType = sampleType
        self.anchorData = anchorData
        self.lastSyncDate = lastSyncDate
    }
}
