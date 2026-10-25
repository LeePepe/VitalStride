import Foundation
import SwiftData
import Testing
import VitalModels
@testable import VitalStride

@Suite("ExercisePickerSectionGrouping")
struct ExercisePickerSectionGroupingTests {
    private func sectionNames(_ grouped: [(ExerciseSection, [Exercise])]) -> [(ExerciseSection, [String])] {
        grouped.map { section, items in
            (section, items.map(\.nameEn))
        }
    }

    @Test("Every muscle filter preserves the exact section identity contract")
    func sectionBindingRemainsStableAcrossMuscleFiltering() {
        let exercises = [
            Exercise(nameEn: "Barbell Bench Press", nameZh: "杠铃卧推", muscleGroup: .chest, equipment: .barbell),
            Exercise(nameEn: "Cable Press", nameZh: "绳索推胸", muscleGroup: .chest, equipment: .cable),
            Exercise(nameEn: "Dumbbell Row", nameZh: "哑铃划船", muscleGroup: .back, equipment: .dumbbell),
            Exercise(nameEn: "Single Arm Resistance Band Row", nameZh: "单臂弹力带划船", muscleGroup: .back, equipment: .resistanceBand),
            Exercise(nameEn: "Machine Shoulder Press", nameZh: "机器肩推", muscleGroup: .shoulders, equipment: .machine),
            Exercise(nameEn: "Kettlebell Curl", nameZh: "壶铃弯举", muscleGroup: .arms, equipment: .kettlebell),
            Exercise(nameEn: "Bodyweight Squat", nameZh: "自重深蹲", muscleGroup: .legs, equipment: .bodyweight),
            Exercise(nameEn: "Band Crunch", nameZh: "弹力带卷腹", muscleGroup: .core, equipment: .band),
            Exercise(nameEn: "Weighted Pull", nameZh: "负重拉力", muscleGroup: .fullBody, equipment: .weighted),
            Exercise(nameEn: "Medicine Ball Slam", nameZh: "药球砸地", muscleGroup: .fullBody, equipment: .medicineBall)
        ]

        for muscleGroup in MuscleGroup.allCases {
            let filtered = ExercisePickerSectionGrouping.groupedSections(from: exercises, muscleGroup: muscleGroup)
            let expected = ExerciseSection.allCases.compactMap { section -> (ExerciseSection, [Exercise])? in
                let items = exercises.filter { $0.muscleGroup == muscleGroup && $0.section == section }
                guard !items.isEmpty else { return nil }
                return (section, items)
            }

            let filteredNames = sectionNames(filtered)
            let expectedNames = sectionNames(expected)
            #expect(filteredNames.count == expectedNames.count)
            for (actual, expected) in zip(filteredNames, expectedNames) {
                #expect(actual.0 == expected.0)
                #expect(actual.1 == expected.1)
            }
            #expect(filtered.allSatisfy { section, items in
                !items.isEmpty && items.allSatisfy { $0.section == section }
            })
            #expect(filtered.flatMap(\.1).allSatisfy { $0.muscleGroup == muscleGroup })
        }
    }

    @Test("Search filtering preserves section identity and nonempty buckets")
    func sectionBindingRemainsStableAcrossSearchFiltering() {
        let exercises = [
            Exercise(nameEn: "Barbell Bench Press", nameZh: "杠铃卧推", muscleGroup: .chest, equipment: .barbell),
            Exercise(nameEn: "Cable Press", nameZh: "绳索推胸", muscleGroup: .chest, equipment: .cable),
            Exercise(nameEn: "Machine Shoulder Press", nameZh: "机器肩推", muscleGroup: .shoulders, equipment: .machine),
            Exercise(nameEn: "Dumbbell Row", nameZh: "哑铃划船", muscleGroup: .back, equipment: .dumbbell),
            Exercise(nameEn: "Weighted Pull", nameZh: "负重拉力", muscleGroup: .fullBody, equipment: .weighted),
            Exercise(nameEn: "Medicine Ball Slam", nameZh: "药球砸地", muscleGroup: .fullBody, equipment: .medicineBall)
        ]

        let searched = ExercisePickerSectionGrouping.groupedSections(from: exercises, searchText: "press")
        let expected = ExerciseSection.allCases.compactMap { section -> (ExerciseSection, [Exercise])? in
            let items = exercises.filter { $0.nameEn.localizedCaseInsensitiveContains("press") && $0.section == section }
            guard !items.isEmpty else { return nil }
            return (section, items)
        }

        let searchedNames = sectionNames(searched)
        let expectedNames = sectionNames(expected)
        #expect(searchedNames.count == expectedNames.count)
        for (actual, expected) in zip(searchedNames, expectedNames) {
            #expect(actual.0 == expected.0)
            #expect(actual.1 == expected.1)
        }
        #expect(searched.allSatisfy { section, items in
            !items.isEmpty && items.allSatisfy { $0.section == section }
        })
        #expect(searched.flatMap(\.1).map(\.nameEn) == ["Barbell Bench Press", "Cable Press", "Machine Shoulder Press"])
    }

    @Test("Custom exercises still map through equipment to the fixed section contract")
    func customExercisesMapToEquipmentSection() {
        let assisted = Exercise(
            nameEn: "Custom Assisted Dip",
            nameZh: "自定义辅助深蹲",
            muscleGroup: .fullBody,
            equipment: .assisted,
            isCustom: true
        )
        let weighted = Exercise(
            nameEn: "Custom Weighted Pull",
            nameZh: "自定义负重拉力",
            muscleGroup: .back,
            equipment: .weighted,
            isCustom: true
        )
        let custom = Exercise(
            nameEn: "Custom Wheel Roller Push",
            nameZh: "自定义轮式滚轮推举",
            muscleGroup: .fullBody,
            equipment: .wheelRoller,
            isCustom: true
        )

        let grouped = ExercisePickerSectionGrouping.groupedSections(from: [assisted, weighted, custom])

        #expect(grouped.map(\.0) == [.bodyweight, .weighted, .other])
        #expect(grouped.allSatisfy { section, items in
            items.allSatisfy { $0.section == section }
        })
        #expect(assisted.section == .bodyweight)
        #expect(weighted.section == .weighted)
        #expect(custom.section == .other)
    }
}

@Suite("ExercisePicker character index scrubbing")
struct ExercisePickerCharacterIndexTests {
    @Test("Index covers every section with exactly one localized character")
    func markers() {
        let markers = ExerciseSection.allCases.map { ExercisePickerSectionGrouping.indexCharacter(for: $0) }
        #expect(markers.allSatisfy { $0.count == 1 })
        #expect(Set(markers).count == markers.count)
    }

    @Test("Scrubbing clamps, crosses section boundaries and handles filtered or empty rails")
    func scrub() {
        let sections: [ExerciseSection] = [.barbell, .cable, .dumbbell]
        #expect(ExercisePickerSectionGrouping.indexSection(at: -20, height: 120, sections: sections) == .barbell)
        #expect(ExercisePickerSectionGrouping.indexSection(at: 40, height: 120, sections: sections) == .cable)
        #expect(ExercisePickerSectionGrouping.indexSection(at: 119, height: 120, sections: sections) == .dumbbell)
        #expect(ExercisePickerSectionGrouping.indexSection(at: 500, height: 120, sections: sections) == .dumbbell)
        #expect(ExercisePickerSectionGrouping.indexSection(at: 20, height: 44, sections: [.machine]) == .machine)
        #expect(ExercisePickerSectionGrouping.indexSection(at: 20, height: 100, sections: []) == nil)
        #expect(ExercisePickerSectionGrouping.indexSection(at: 20, height: 0, sections: sections) == nil)
        #expect(ExercisePickerSectionGrouping.indexSection(at: .nan, height: 120, sections: sections) == nil)
    }
}

@Suite("ExercisePicker custom exercise persistence")
@MainActor
struct ExercisePickerCustomExerciseTests {
    @Test("Create then edit a custom exercise round-trips without replacing its identity")
    func createAndEdit() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let exercise = try PickerExerciseEditor.save(exercise: nil, nameEn: "  Test press  ", nameZh: "",
            muscleGroup: .chest, equipment: .barbell, context: context)
        let id = exercise.persistentModelID
        #expect(exercise.isCustom)
        #expect(exercise.localizedName == "Test press")
        #expect(PickerExerciseEditor.canDelete(exercise))
        try PickerExerciseEditor.save(exercise: exercise, nameEn: "Custom row", nameZh: "",
            muscleGroup: .back, equipment: .cable, context: context)
        let stored = try #require(context.fetch(FetchDescriptor<Exercise>()).first)
        #expect(stored.persistentModelID == id)
        #expect(stored.nameEn == "Custom row")
        #expect(stored.muscleGroup == .back)
        #expect(stored.equipment == .cable)
        let groups = ExercisePickerSectionGrouping.groupedSections(from: [stored], muscleGroup: .back, searchText: "row")
        #expect(groups.map(\.0) == [.cable])
    }

    @Test("Invalid names and preset edits do not mutate the library")
    func invalidEdits() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        #expect(throws: PickerExerciseEditor.SaveError.invalidName) {
            try PickerExerciseEditor.save(exercise: nil, nameEn: " \n", nameZh: " ",
                muscleGroup: .chest, equipment: .barbell, context: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Exercise>()) == 0)
        let preset = Exercise(nameEn: "Preset", nameZh: "", muscleGroup: .chest, equipment: .barbell)
        context.insert(preset)
        try context.save()
        #expect(throws: PickerExerciseEditor.SaveError.presetReadOnly) {
            try PickerExerciseEditor.save(exercise: preset, nameEn: "Changed", nameZh: "",
                muscleGroup: .back, equipment: .cable, context: context)
        }
        #expect(preset.nameEn == "Preset")
        #expect(!PickerExerciseEditor.canDelete(preset))
    }

    @Test("Referenced custom exercises cannot be deleted from workout or template history")
    func usedExerciseIsProtected() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let custom = try PickerExerciseEditor.save(exercise: nil, nameEn: "Custom", nameZh: "",
            muscleGroup: .chest, equipment: .barbell, context: context)
        let row = WorkoutExercise(order: 0, exercise: custom)
        context.insert(row)
        try context.save()
        #expect(!PickerExerciseEditor.canDelete(custom))
        let templateOnly = try PickerExerciseEditor.save(exercise: nil, nameEn: "Template custom", nameZh: "",
            muscleGroup: .legs, equipment: .dumbbell, context: context)
        let templateRow = TemplateExercise(exercise: templateOnly, targetSets: 3, order: 0)
        context.insert(templateRow)
        try context.save()
        #expect(!PickerExerciseEditor.canDelete(templateOnly))
    }
}
