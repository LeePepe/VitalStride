import Foundation
import Testing
import VitalModels
@testable import VitalStride

@Suite("ExercisePickerSectionGrouping")
struct ExercisePickerSectionGroupingTests {
    @Test("Section grouping keeps stable identities across filters and search")
    func sectionBindingRemainsStableAcrossFiltering() {
        let exercises = [
            Exercise(nameEn: "Barbell Bench Press", nameZh: "杠铃卧推", muscleGroup: .chest, equipment: .barbell),
            Exercise(nameEn: "Cable Press", nameZh: "绳索推胸", muscleGroup: .chest, equipment: .cable),
            Exercise(nameEn: "Dumbbell Row", nameZh: "哑铃划船", muscleGroup: .back, equipment: .dumbbell),
            Exercise(nameEn: "Single Arm Resistance Band Row", nameZh: "单臂弹力带划船", muscleGroup: .back, equipment: .resistanceBand),
            Exercise(nameEn: "Machine Shoulder Press", nameZh: "机器肩推", muscleGroup: .shoulders, equipment: .machine)
        ]

        let filteredByMuscle = ExercisePickerSectionGrouping.groupedSections(
            from: exercises,
            muscleGroup: .chest,
            searchText: ""
        )
        #expect(filteredByMuscle.map(\.0) == [.barbell, .cable])
        #expect(filteredByMuscle.allSatisfy { section, items in
            items.allSatisfy { $0.section == section }
        })

        let searched = ExercisePickerSectionGrouping.groupedSections(
            from: exercises,
            muscleGroup: nil,
            searchText: "press"
        )
        #expect(searched.map(\.0) == [.barbell, .cable, .machine])
        #expect(searched.allSatisfy { section, items in
            items.allSatisfy { $0.section == section }
        })
    }

    @Test("Custom exercises still map through equipment to the fixed section contract")
    func customExercisesMapToEquipmentSection() {
        let custom = Exercise(
            nameEn: "Custom Wheel Roller Push",
            nameZh: "自定义轮式滚轮推举",
            muscleGroup: .fullBody,
            equipment: .wheelRoller,
            isCustom: true
        )

        let grouped = ExercisePickerSectionGrouping.groupedSections(from: [custom])

        #expect(grouped.count == 1)
        #expect(grouped[0].0 == .other)
        #expect(grouped[0].1 == [custom])
        #expect(custom.section == .other)
    }
}
