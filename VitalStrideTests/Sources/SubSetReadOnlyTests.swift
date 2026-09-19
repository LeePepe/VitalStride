import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("SubSet editable row invariants (MY-1484)")
struct SubSetReadOnlyTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("Sub-set rows keep the shared editable row composition contract")
    func subSetRowsUseSharedEditableComposition() throws {
        let context = ModelContext(container)
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let parent = ExerciseSet(order: 0, weight: 80, reps: 8, setType: .working)
        let pyramid = ExerciseSet(order: 1, weight: 90, reps: 8, setType: .pyramid)
        let drop = ExerciseSet(order: 2, weight: 70, reps: 8, setType: .dropSet)
        [parent, pyramid, drop].forEach { context.insert($0) }

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [parent, pyramid, drop])
        context.insert(workoutExercise)

        let contexts = ActiveExerciseSection.rowContexts(from: [parent, pyramid, drop])
        #expect(contexts.map(\.mainSetNumber) == [0, 1, 1])
        #expect(contexts.map(\.exerciseSet.setType.isSubSet) == [false, true, true])
    }

    @Test("Sub-set delete identity composes parent number, type, and delete intent")
    func subSetDeleteIdentityUsesParentAndType() {
        let identity = SetRowIdentity(displayedMainSetNumber: 2, currentSetType: .pyramid, isSubSet: true)
        #expect(identity.accessibilityLabel.contains("第 2 组") )
        #expect(identity.accessibilityLabel.contains("金字塔") || identity.accessibilityLabel.contains("锥形") || identity.accessibilityLabel.contains("锥形") || identity.accessibilityLabel.contains("金字塔"))
        #expect(identity.accessibilityLabel.contains("删除"))
    }
}
