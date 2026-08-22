import Testing
@testable import VitalModels

@Suite("ExerciseSection Tests")
struct ExerciseSectionTests {

    @Test("ExerciseSection exposes the stable 17 picker sections")
    func stableSectionCount() {
        let expected: [String] = [
            "assisted",
            "band",
            "barbell",
            "bodyweight",
            "cable",
            "dumbbell",
            "ez_barbell",
            "kettlebell",
            "leverage_machine",
            "machine",
            "medicine_ball",
            "other",
            "rope",
            "sled_machine",
            "smith_machine",
            "stability_ball",
            "weighted",
        ]

        let actual = ExerciseSection.allCases.map(\.rawValue)
        #expect(actual.count == 17)
        #expect(Set(actual) == Set(expected))
    }

    @Test("Equipment resolves the stable section mapping and pushes low-frequency equipment into other")
    func equipmentSectionMapping() {
        #expect(Equipment.assisted.section == .assisted)
        #expect(Equipment.band.section == .band)
        #expect(Equipment.barbell.section == .barbell)
        #expect(Equipment.bodyweight.section == .bodyweight)
        #expect(Equipment.cable.section == .cable)
        #expect(Equipment.dumbbell.section == .dumbbell)
        #expect(Equipment.ezBarbell.section == .ezBarbell)
        #expect(Equipment.kettlebell.section == .kettlebell)
        #expect(Equipment.leverageMachine.section == .leverageMachine)
        #expect(Equipment.machine.section == .machine)
        #expect(Equipment.medicineBall.section == .medicineBall)
        #expect(Equipment.rope.section == .rope)
        #expect(Equipment.sledMachine.section == .sledMachine)
        #expect(Equipment.smithMachine.section == .smithMachine)
        #expect(Equipment.stabilityBall.section == .stabilityBall)
        #expect(Equipment.weighted.section == .weighted)

        #expect(Equipment.bosuBall.section == .other)
        #expect(Equipment.ellipticalMachine.section == .other)
        #expect(Equipment.hammer.section == .other)
        #expect(Equipment.olympicBarbell.section == .other)
        #expect(Equipment.resistanceBand.section == .other)
        #expect(Equipment.roller.section == .other)
        #expect(Equipment.skiergMachine.section == .other)
        #expect(Equipment.sledMachine.section == .sledMachine)
        #expect(Equipment.stationaryBike.section == .other)
        #expect(Equipment.stepmillMachine.section == .other)
        #expect(Equipment.tire.section == .other)
        #expect(Equipment.trapBar.section == .other)
        #expect(Equipment.upperBodyErgometer.section == .other)
        #expect(Equipment.wheelRoller.section == .other)
    }

    @Test("Exercise.section is derived from its equipment without changing persisted schema")
    func exerciseSectionDerivesFromEquipment() {
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )

        #expect(exercise.section == .barbell)
        #expect(exercise.equipment == .barbell)
        #expect(exercise.section == exercise.equipment.section)
    }

    @Test("ExerciseSection SF Symbols are non-empty and unique")
    func sectionSymbolsAreUnique() {
        let symbols = ExerciseSection.allCases.map(\.sfSymbol)
        #expect(symbols.allSatisfy { !$0.isEmpty })
        #expect(Set(symbols).count == symbols.count)
    }
}
