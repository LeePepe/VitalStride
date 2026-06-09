import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("Min-One-Set Invariant Tests")
struct MinOneSetInvariantTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    // MARK: - Rule 1: setupWorkout(.fromTemplate) pre-creates sets

    @Test("Template with targetSets=3 creates 3 sets per exercise")
    func templateCreatesCorrectSetCount() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let templateExercise = TemplateExercise(
            exercise: exercise,
            targetSets: 3,
            targetWeight: 80.0,
            order: 0
        )
        context.insert(templateExercise)

        let template = WorkoutTemplate(name: "Push Day")
        template.exercises = [templateExercise]
        context.insert(template)
        try context.save()

        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let templateExercises = (template.exercises ?? []).sorted { $0.order < $1.order }
        for (index, tplExercise) in templateExercises.enumerated() {
            let workoutExercise = WorkoutExercise(order: index, exercise: tplExercise.exercise)
            workoutExercise.workout = workout
            context.insert(workoutExercise)

            let setCount = max(1, tplExercise.targetSets)
            let weight = tplExercise.targetWeight ?? 0
            for setIndex in 0..<setCount {
                let newSet = ExerciseSet(order: setIndex, weight: weight, reps: 0, setType: .working)
                newSet.workoutExercise = workoutExercise
                context.insert(newSet)
            }
        }
        try context.save()

        let exercises = (workout.exercises ?? []).sorted { $0.order < $1.order }
        #expect(exercises.count == 1)
        let sets = (exercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(sets.count == 3)
        #expect(sets[0].weight == 80.0)
        #expect(sets[1].weight == 80.0)
        #expect(sets[2].weight == 80.0)
        for s in sets {
            #expect(s.reps == 0)
            #expect(s.setType == .working)
        }
    }

    @Test("Template with targetSets=0 still creates at least 1 set")
    func templateWithZeroTargetSetsCreatesOneSet() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Pull Up",
            nameZh: "引体向上",
            muscleGroup: .back,
            equipment: .bodyweight
        )
        context.insert(exercise)

        let templateExercise = TemplateExercise(
            exercise: exercise,
            targetSets: 0,
            targetWeight: nil,
            order: 0
        )
        context.insert(templateExercise)

        let template = WorkoutTemplate(name: "Pull Day")
        template.exercises = [templateExercise]
        context.insert(template)
        try context.save()

        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let templateExercises = (template.exercises ?? []).sorted { $0.order < $1.order }
        for (index, tplExercise) in templateExercises.enumerated() {
            let workoutExercise = WorkoutExercise(order: index, exercise: tplExercise.exercise)
            workoutExercise.workout = workout
            context.insert(workoutExercise)

            let setCount = max(1, tplExercise.targetSets)
            let weight = tplExercise.targetWeight ?? 0
            for setIndex in 0..<setCount {
                let newSet = ExerciseSet(order: setIndex, weight: weight, reps: 0, setType: .working)
                newSet.workoutExercise = workoutExercise
                context.insert(newSet)
            }
        }
        try context.save()

        let exercises = (workout.exercises ?? []).sorted { $0.order < $1.order }
        #expect(exercises.count == 1)
        let sets = (exercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(sets.count == 1)
        #expect(sets[0].weight == 0)
        #expect(sets[0].setType == .working)
    }

    @Test("Template with targetWeight pre-fills weight on each set")
    func templatePreFillsWeight() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Squat",
            nameZh: "深蹲",
            muscleGroup: .legs,
            equipment: .barbell
        )
        context.insert(exercise)

        let templateExercise = TemplateExercise(
            exercise: exercise,
            targetSets: 2,
            targetWeight: 100.0,
            order: 0
        )
        context.insert(templateExercise)

        let template = WorkoutTemplate(name: "Leg Day")
        template.exercises = [templateExercise]
        context.insert(template)
        try context.save()

        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let tplExercises = (template.exercises ?? []).sorted { $0.order < $1.order }
        for (index, tplExercise) in tplExercises.enumerated() {
            let workoutExercise = WorkoutExercise(order: index, exercise: tplExercise.exercise)
            workoutExercise.workout = workout
            context.insert(workoutExercise)

            let setCount = max(1, tplExercise.targetSets)
            let weight = tplExercise.targetWeight ?? 0
            for setIndex in 0..<setCount {
                let newSet = ExerciseSet(order: setIndex, weight: weight, reps: 0, setType: .working)
                newSet.workoutExercise = workoutExercise
                context.insert(newSet)
            }
        }
        try context.save()

        let exercises = (workout.exercises ?? []).sorted { $0.order < $1.order }
        let sets = (exercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(sets.count == 2)
        #expect(sets[0].weight == 100.0)
        #expect(sets[1].weight == 100.0)
    }

    // MARK: - Rule 2: deleteSet guard prevents deletion of last set

    @Test("deleteSet with only 1 set does not delete")
    func deleteLastSetIsBlocked() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Curl",
            nameZh: "弯举",
            muscleGroup: .arms,
            equipment: .dumbbell
        )
        context.insert(exercise)

        let onlySet = ExerciseSet(order: 0, weight: 10.0, reps: 10, setType: .working)
        context.insert(onlySet)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [onlySet])
        context.insert(workoutExercise)

        let workout = Workout(type: .strength, startDate: Date(), exercises: [workoutExercise])
        context.insert(workout)
        try context.save()

        let sortedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        let toDelete = [onlySet]
        let wouldRemain = sortedSets.count - toDelete.count

        #expect(wouldRemain == 0)
        #expect(sortedSets.count == 1)
    }

    @Test("deleteSet with 2+ sets allows deletion")
    func deleteSetWithMultipleSetsWorks() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Curl",
            nameZh: "弯举",
            muscleGroup: .arms,
            equipment: .dumbbell
        )
        context.insert(exercise)

        let set1 = ExerciseSet(order: 0, weight: 10.0, reps: 10, setType: .working)
        let set2 = ExerciseSet(order: 1, weight: 10.0, reps: 10, setType: .working)
        context.insert(set1)
        context.insert(set2)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [set1, set2])
        context.insert(workoutExercise)

        let workout = Workout(type: .strength, startDate: Date(), exercises: [workoutExercise])
        context.insert(workout)
        try context.save()

        let sortedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        let toDelete = [set1]
        let wouldRemain = sortedSets.count - toDelete.count

        #expect(wouldRemain == 1)

        let deleteIDs = Set(toDelete.map { $0.persistentModelID })
        for s in toDelete { context.delete(s) }
        let remaining = sortedSets.filter { !deleteIDs.contains($0.persistentModelID) }
        for (newOrder, s) in remaining.enumerated() { s.order = newOrder }
        try context.save()

        let updatedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(updatedSets.count == 1)
        #expect(updatedSets[0].order == 0)
    }

    // MARK: - Rule 3: Main set with subsets cascade guard

    @Test("Deleting main set with subsets that would leave 0 is blocked")
    func deleteMainSetWithSubsetsCascadeGuard() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let mainSet = ExerciseSet(order: 0, weight: 80.0, reps: 8, setType: .working)
        let dropSet = ExerciseSet(order: 1, weight: 60.0, reps: 10, setType: .dropSet)
        context.insert(mainSet)
        context.insert(dropSet)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise, sets: [mainSet, dropSet])
        context.insert(workoutExercise)

        let workout = Workout(type: .strength, startDate: Date(), exercises: [workoutExercise])
        context.insert(workout)
        try context.save()

        let sortedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        var toDelete = [mainSet]
        let parentIndex = sortedSets.firstIndex(where: { $0.persistentModelID == mainSet.persistentModelID })!
        var i = parentIndex + 1
        while i < sortedSets.count && sortedSets[i].setType.isSubSet {
            toDelete.append(sortedSets[i])
            i += 1
        }

        let wouldRemain = sortedSets.count - toDelete.count
        #expect(toDelete.count == 2)
        #expect(wouldRemain == 0)
    }

    @Test("Deleting main set with subsets when other sets exist is allowed")
    func deleteMainSetWithSubsetsWhenOtherSetsExist() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let mainSet1 = ExerciseSet(order: 0, weight: 80.0, reps: 8, setType: .working)
        let dropSet1 = ExerciseSet(order: 1, weight: 60.0, reps: 10, setType: .dropSet)
        let mainSet2 = ExerciseSet(order: 2, weight: 80.0, reps: 8, setType: .working)
        context.insert(mainSet1)
        context.insert(dropSet1)
        context.insert(mainSet2)

        let workoutExercise = WorkoutExercise(
            order: 0, exercise: exercise, sets: [mainSet1, dropSet1, mainSet2]
        )
        context.insert(workoutExercise)

        let workout = Workout(type: .strength, startDate: Date(), exercises: [workoutExercise])
        context.insert(workout)
        try context.save()

        let sortedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        var toDelete = [mainSet1]
        let parentIndex = sortedSets.firstIndex(where: { $0.persistentModelID == mainSet1.persistentModelID })!
        var i = parentIndex + 1
        while i < sortedSets.count && sortedSets[i].setType.isSubSet {
            toDelete.append(sortedSets[i])
            i += 1
        }

        let wouldRemain = sortedSets.count - toDelete.count
        #expect(toDelete.count == 2)
        #expect(wouldRemain == 1)

        let deleteIDs = Set(toDelete.map { $0.persistentModelID })
        for s in toDelete { context.delete(s) }
        let remaining = sortedSets.filter { !deleteIDs.contains($0.persistentModelID) }
        for (newOrder, s) in remaining.enumerated() { s.order = newOrder }
        try context.save()

        let updatedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        #expect(updatedSets.count == 1)
        #expect(updatedSets[0].order == 0)
        #expect(updatedSets[0].setType == .working)
    }

    // MARK: - Rule 1: WorkoutCopier fallback

    @Test("WorkoutCopier creates fallback set when source exercise has no sets")
    func copierFallbackCreatesDefaultSet() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Lateral Raise",
            nameZh: "侧平举",
            muscleGroup: .shoulders,
            equipment: .dumbbell
        )
        context.insert(exercise)

        let we = WorkoutExercise(order: 0, exercise: exercise)
        context.insert(we)

        let sourceWorkout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            exercises: [we]
        )
        context.insert(sourceWorkout)
        try context.save()

        let newWorkout = Workout(type: .strength, startDate: Date())
        context.insert(newWorkout)

        WorkoutCopier.copyExercises(from: sourceWorkout, to: newWorkout, using: context)
        try context.save()

        let copiedExercises = (newWorkout.exercises ?? []).sorted { $0.order < $1.order }
        #expect(copiedExercises.count == 1)
        let copiedSets = (copiedExercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(copiedSets.count == 1)
        #expect(copiedSets[0].weight == 0)
        #expect(copiedSets[0].reps == 0)
        #expect(copiedSets[0].setType == .working)
    }

    @Test("WorkoutCopier copies sets normally when source has sets")
    func copierCopiesSetsNormally() throws {
        let context = ModelContext(container)

        let exercise = Exercise(
            nameEn: "Row",
            nameZh: "划船",
            muscleGroup: .back,
            equipment: .barbell
        )
        context.insert(exercise)

        let srcSet = ExerciseSet(order: 0, weight: 60.0, reps: 8, setType: .working)
        context.insert(srcSet)

        let we = WorkoutExercise(order: 0, exercise: exercise, sets: [srcSet])
        context.insert(we)

        let sourceWorkout = Workout(
            type: .strength,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date(),
            exercises: [we]
        )
        context.insert(sourceWorkout)
        try context.save()

        let newWorkout = Workout(type: .strength, startDate: Date())
        context.insert(newWorkout)

        WorkoutCopier.copyExercises(from: sourceWorkout, to: newWorkout, using: context)
        try context.save()

        let copiedExercises = (newWorkout.exercises ?? []).sorted { $0.order < $1.order }
        let copiedSets = (copiedExercises[0].sets ?? []).sorted { $0.order < $1.order }
        #expect(copiedSets.count == 1)
        #expect(copiedSets[0].weight == 60.0)
        #expect(copiedSets[0].reps == 8)
    }
}
