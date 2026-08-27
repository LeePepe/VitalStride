import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("ActiveExerciseSection add-set header")
struct ActiveExerciseSectionAddSetHeaderTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("Header contains the add-set action while the section content contains only set rows")
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
        guard let firstConfirmation = source.range(
            of: ".confirmationDialog(",
            range: headerStart.upperBound..<source.endIndex
        ) else {
            Issue.record("Expected the section header to end before the confirmation dialog.")
            return
        }

        let sectionBody = source[sectionStart.lowerBound..<headerStart.lowerBound]
        let headerBody = source[headerStart.lowerBound..<firstConfirmation.lowerBound]

        #expect(
            !sectionBody.contains("addSetButton"),
            "Section content still contains the add-set action. It must stay out of the `Section` content and live in the header beside the exercise title + menu."
        )
        #expect(
            headerBody.contains("addSetButton"),
            "The exercise header should contain the add-set action next to the title and menu controls."
        )
        #expect(
            sectionBody.contains("ForEach"),
            "Section content should still render the main-set and sub-set rows."
        )
    }

    @Test("One append copies the last main-set defaults and keeps the next continuous order")
    func addSetCopiesLastMainSetDefaultsAndContinuousOrder() throws {
        let context = ModelContext(container)
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let mainSet = ExerciseSet(
            order: 0,
            weight: 80,
            reps: 8,
            setType: .working,
            isUnilateral: false,
            weightRight: nil
        )
        let lastMainSet = ExerciseSet(
            order: 1,
            weight: 90,
            reps: 6,
            setType: .working,
            isUnilateral: true,
            weightRight: 92
        )
        let trailingSubSet = ExerciseSet(
            order: 2,
            weight: 70,
            reps: 12,
            setType: .dropSet,
            isUnilateral: true,
            weightRight: 74
        )

        let workoutExercise = WorkoutExercise(
            order: 0,
            exercise: exercise,
            sets: [mainSet, lastMainSet, trailingSubSet]
        )
        context.insert(workoutExercise)

        let appendedSet = ActiveExerciseSection.insertAppendedMainSet(
            in: workoutExercise,
            using: context
        )

        #expect(appendedSet.weight == 90)
        #expect(appendedSet.reps == 6)
        #expect(appendedSet.setType == .working)
        #expect(appendedSet.isUnilateral == true)
        #expect(appendedSet.weightRight == 92)
        #expect(appendedSet.order == 3)
        #expect(appendedSet.workoutExercise?.persistentModelID == workoutExercise.persistentModelID)

        let orderedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(orderedSets.count == 4)
        #expect(orderedSets.map(\.order) == [0, 1, 2, 3])
        #expect(orderedSets.last?.persistentModelID == appendedSet.persistentModelID)
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
