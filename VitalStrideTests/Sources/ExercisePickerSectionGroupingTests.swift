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
