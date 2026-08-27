import Foundation
import Testing

@Suite("ActiveExerciseSection add-set header")
struct ActiveExerciseSectionAddSetHeaderTests {
    @Test("Section content no longer contains the add-set action (header placement regression)")
    func sectionContentOmitsAddSetButton() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let sectionStart = source.range(of: "return Section {") else {
            Issue.record("Expected ActiveExerciseSection.body to start with `return Section {`.")
            return
        }
        guard let headerStart = source.range(of: "header: {") else {
            Issue.record("Expected ActiveExerciseSection.body to declare a header.")
            return
        }

        let sectionBody = source[sectionStart.lowerBound..<headerStart.lowerBound]

        #expect(
            !sectionBody.contains("addSetButton"),
            "Section content still contains the add-set action. It must stay out of the `Section` content and live in the header beside the exercise title + menu."
        )
        #expect(
            sectionBody.contains("ForEach"),
            "Section content should still render the main-set and sub-set rows."
        )
    }

    @Test("The add-set button keeps its existing localized label and insertion hint")
    func addSetButtonRetainsLocalizationContract() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(
            source.contains("String(localized: \"添加一组\", comment: \"Add set button a11y\")"),
            "The add-set action should keep the existing localized label contract."
        )
        #expect(
            source.contains("String(localized: \"在列表末尾插入新的一组\", comment: \"Add set hint\")"),
            "The add-set action should keep the existing insertion hint contract."
        )
    }
}
