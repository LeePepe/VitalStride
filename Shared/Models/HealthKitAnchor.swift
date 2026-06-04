import Foundation
import SwiftData

@Model
final class HealthKitAnchor {
    var sampleType: HealthSampleType = HealthSampleType.heartRate
    var deviceIdentifier: String = ""
    var anchorData: Data = Data()
    var lastSyncDate: Date = Date()

    init(
        sampleType: HealthSampleType,
        deviceIdentifier: String,
        anchorData: Data,
        lastSyncDate: Date = Date()
    ) {
        self.sampleType = sampleType
        self.deviceIdentifier = deviceIdentifier
        self.anchorData = anchorData
        self.lastSyncDate = lastSyncDate
    }
}
