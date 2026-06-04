import Foundation
import SwiftData

@Model
final class HealthSample {
    var id: UUID = UUID()
    var sampleType: HealthSampleType = HealthSampleType.heartRate
    var value: Double = 0.0
    var unit: String?
    var startDate: Date = Date()
    var endDate: Date = Date()
    var sourceDevice: String?

    init(
        sampleType: HealthSampleType,
        value: Double,
        unit: String? = nil,
        startDate: Date,
        endDate: Date,
        sourceDevice: String? = nil
    ) {
        self.id = UUID()
        self.sampleType = sampleType
        self.value = value
        self.unit = unit
        self.startDate = startDate
        self.endDate = endDate
        self.sourceDevice = sourceDevice
    }
}
