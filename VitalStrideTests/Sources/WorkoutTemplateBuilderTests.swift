import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

@Suite("WorkoutTemplateBuilder")
@MainActor
struct WorkoutTemplateBuilderTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    private func makeExercise(_ name: String, in context: ModelContext) -> Exercise {
        let exercise = Exercise(
            nameEn: name,
            nameZh: name,
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)
        return exercise
    }

    private func makeWorkoutExercise(
        exercise: Exercise,
        order: Int,
        setSpecs: [(weight: Double, setType: SetType)],
        in workout: Workout,
        context: ModelContext
    ) -> WorkoutExercise {
        let workoutExercise = WorkoutExercise(order: order, exercise: exercise)
        workoutExercise.workout = workout
        context.insert(workoutExercise)
        for (index, spec) in setSpecs.enumerated() {
            let set = ExerciseSet(
                order: index,
                weight: spec.weight,
                reps: 8,
                setType: spec.setType
            )
            set.workoutExercise = workoutExercise
            context.insert(set)
        }
        return workoutExercise
    }

    @Test("saveAsTemplate excludes warmup sets from targetSets and targetWeight")
    func excludesWarmupSets() throws {
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let bench = makeExercise("Bench Press", in: context)
        _ = makeWorkoutExercise(
            exercise: bench,
            order: 0,
            setSpecs: [
                (40.0, .warmup),
                (60.0, .warmup),
                (100.0, .working),
                (100.0, .working),
                (100.0, .working)
            ],
            in: workout,
            context: context
        )
        try context.save()

        let template = try WorkoutTemplateBuilder.saveAsTemplate(
            from: workout,
            name: "Push Day",
            context: context
        )

        let exercises = (template.exercises ?? []).sorted { $0.order < $1.order }
        #expect(exercises.count == 1)
        #expect(exercises[0].targetSets == 3)
        #expect(exercises[0].targetWeight == 100.0)
        #expect(template.name == "Push Day")
    }

    @Test("saveAsTemplate targetWeight is the average of working set weights")
    func averagesWorkingSetWeights() throws {
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let squat = makeExercise("Back Squat", in: context)
        _ = makeWorkoutExercise(
            exercise: squat,
            order: 0,
            setSpecs: [
                (100.0, .working),
                (110.0, .working),
                (120.0, .working)
            ],
            in: workout,
            context: context
        )
        try context.save()

        let template = try WorkoutTemplateBuilder.saveAsTemplate(
            from: workout,
            name: "Leg Day",
            context: context
        )

        let exercises = (template.exercises ?? []).sorted { $0.order < $1.order }
        #expect(exercises.count == 1)
        #expect(exercises[0].targetSets == 3)
        #expect(exercises[0].targetWeight == 110.0)
    }

    @Test("saveAsTemplate preserves workout exercise ordering")
    func preservesOrder() throws {
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let bench = makeExercise("Bench Press", in: context)
        let row = makeExercise("Barbell Row", in: context)
        let curl = makeExercise("Bicep Curl", in: context)

        _ = makeWorkoutExercise(exercise: bench, order: 0, setSpecs: [(80.0, .working)], in: workout, context: context)
        _ = makeWorkoutExercise(exercise: row, order: 1, setSpecs: [(70.0, .working)], in: workout, context: context)
        _ = makeWorkoutExercise(exercise: curl, order: 2, setSpecs: [(15.0, .working)], in: workout, context: context)
        try context.save()

        let template = try WorkoutTemplateBuilder.saveAsTemplate(
            from: workout,
            name: "Full Body",
            context: context
        )

        let exercises = (template.exercises ?? []).sorted { $0.order < $1.order }
        #expect(exercises.count == 3)
        #expect(exercises[0].order == 0)
        #expect(exercises[0].exercise?.nameEn == "Bench Press")
        #expect(exercises[1].order == 1)
        #expect(exercises[1].exercise?.nameEn == "Barbell Row")
        #expect(exercises[2].order == 2)
        #expect(exercises[2].exercise?.nameEn == "Bicep Curl")
    }

    @Test("saveAsTemplate with only warmup sets yields targetSets=0 and nil targetWeight")
    func onlyWarmupSets() throws {
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let bench = makeExercise("Bench Press", in: context)
        _ = makeWorkoutExercise(
            exercise: bench,
            order: 0,
            setSpecs: [
                (20.0, .warmup),
                (40.0, .warmup)
            ],
            in: workout,
            context: context
        )
        try context.save()

        let template = try WorkoutTemplateBuilder.saveAsTemplate(
            from: workout,
            name: "Warmup Only",
            context: context
        )

        let exercises = (template.exercises ?? []).sorted { $0.order < $1.order }
        #expect(exercises.count == 1)
        #expect(exercises[0].targetSets == 0)
        #expect(exercises[0].targetWeight == nil)
    }

    @Test("saveAsTemplate persists template and can be re-fetched")
    func templateIsPersisted() throws {
        let context = ModelContext(container)
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let bench = makeExercise("Bench Press", in: context)
        _ = makeWorkoutExercise(exercise: bench, order: 0, setSpecs: [(60.0, .working), (65.0, .working)], in: workout, context: context)
        try context.save()

        _ = try WorkoutTemplateBuilder.saveAsTemplate(
            from: workout,
            name: "  Persistable  ",
            context: context
        )

        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>())
        #expect(templates.count == 1)
        #expect(templates[0].name == "Persistable")
        #expect((templates[0].exercises ?? []).count == 1)
    }
}
