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

    @Test("Exercise cards use a solid grouped surface and footer add-set controls")
    func sectionUsesCardFooterAddSet() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("} footer:"))
        #expect(source.contains("private var cardFooter"))
        #expect(source.contains("workoutSecondaryGroupedBackground"))
        #expect(source.contains("accessibilityLabel(String(localized: \"添加一组\", comment: \"Add set button a11y\"))"))
        #expect(source.contains("\"add-set\""))
        #expect(source.contains("workoutSecondaryGroupedBackground"))
        #expect(source.contains("ForEach"))
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
        let neighboringExercise = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        context.insert(neighboringExercise)
        let neighbor = WorkoutExercise(order: 1, exercise: neighboringExercise)
        let neighborSet = ExerciseSet(order: 0, weight: 110, reps: 5)
        neighborSet.workoutExercise = neighbor
        neighbor.sets = [neighborSet]
        context.insert(neighbor)
        context.insert(neighborSet)
        let neighborSnapshot = (neighbor.sets ?? []).sorted { $0.order < $1.order }.map {
            ($0.persistentModelID, $0.order, $0.weight, $0.reps, $0.workoutExercise?.persistentModelID)
        }

        let appendedSet = ActiveExerciseSection.insertAppendedMainSet(
            in: workoutExercise,
            using: context
        )

        #expect(appendedSet.setType == .working)
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
        #expect(orderedSets.filter { !$0.setType.isSubSet }.count == 3)
        #expect(workoutExercise.sets?.contains { $0 === appendedSet } == true)
        #expect(appendedSet.workoutExercise === workoutExercise)

        let neighborAfter = (neighbor.sets ?? []).sorted { $0.order < $1.order }.map {
            ($0.persistentModelID, $0.order, $0.weight, $0.reps, $0.workoutExercise?.persistentModelID)
        }
        #expect(neighborAfter.elementsEqual(neighborSnapshot, by: ==))
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

    @Test("Completed sections render an index badge and collapsed sections can expand")
    func completionAndCollapseContract() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains("workoutExercise.order + 1"))
        #expect(source.contains("if isCollapsed || (completedSetCount == totalSetCount"))
        #expect(source.contains("isCollapsed = false"))
        #expect(source.contains("checkmark.circle.fill"))
    }
}
