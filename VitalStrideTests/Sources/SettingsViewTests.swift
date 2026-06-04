import Foundation
import Testing

@testable import VitalStride

@Suite("Settings View Tests")
struct SettingsViewTests {
    @Test("WeightUnit has correct display names")
    func weightUnitDisplayNames() {
        #expect(WeightUnit.kg.displayName == "公斤 (kg)")
        #expect(WeightUnit.lb.displayName == "磅 (lb)")
    }

    @Test("WeightUnit rawValues for AppStorage")
    func weightUnitRawValues() {
        #expect(WeightUnit.kg.rawValue == "kg")
        #expect(WeightUnit.lb.rawValue == "lb")
    }

    @Test("DistanceUnit has correct display names")
    func distanceUnitDisplayNames() {
        #expect(DistanceUnit.km.displayName == "公里 (km)")
        #expect(DistanceUnit.mi.displayName == "英里 (mi)")
    }

    @Test("DistanceUnit rawValues for AppStorage")
    func distanceUnitRawValues() {
        #expect(DistanceUnit.km.rawValue == "km")
        #expect(DistanceUnit.mi.rawValue == "mi")
    }

    @Test("WeightUnit conforms to CaseIterable")
    func weightUnitCaseIterable() {
        #expect(WeightUnit.allCases.count == 2)
        #expect(WeightUnit.allCases.contains(.kg))
        #expect(WeightUnit.allCases.contains(.lb))
    }

    @Test("DistanceUnit conforms to CaseIterable")
    func distanceUnitCaseIterable() {
        #expect(DistanceUnit.allCases.count == 2)
        #expect(DistanceUnit.allCases.contains(.km))
        #expect(DistanceUnit.allCases.contains(.mi))
    }

    @Test("ExportRange has correct display names")
    func exportRangeDisplayNames() {
        #expect(ExportRange.all.displayName == "全部")
        #expect(ExportRange.lastMonth.displayName == "最近一个月")
        #expect(ExportRange.lastThreeMonths.displayName == "最近三个月")
        #expect(ExportRange.lastYear.displayName == "最近一年")
    }

    @Test("ExportRange conforms to CaseIterable")
    func exportRangeCaseIterable() {
        #expect(ExportRange.allCases.count == 4)
    }

    @Test("ImportedFileRecord creation")
    func importedFileRecordCreation() {
        let now = Date()
        let record = ImportedFileRecord(fileName: "ride.gpx", importDate: now)
        #expect(record.fileName == "ride.gpx")
        #expect(record.importDate == now)
    }

    @Test("ImportedFileRecord has unique IDs")
    func importedFileRecordUniqueIds() {
        let record1 = ImportedFileRecord(fileName: "a.gpx", importDate: Date())
        let record2 = ImportedFileRecord(fileName: "b.fit", importDate: Date())
        #expect(record1.id != record2.id)
    }

    @Test("ExportDocument stores content")
    func exportDocumentContent() {
        let content = "{\"workouts\": []}"
        let document = ExportDocument(content: content)
        #expect(document.content == content)
    }

    @Test("ExportDocument empty content")
    func exportDocumentEmpty() {
        let document = ExportDocument(content: "{}")
        #expect(document.content == "{}")
    }
}
