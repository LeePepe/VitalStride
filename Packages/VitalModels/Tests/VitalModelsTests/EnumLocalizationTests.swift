import Testing
@testable import VitalModels

@Suite("MuscleGroup")
struct MuscleGroupTests {
    @Test("All cases have non-empty localizedName")
    func localizedNameNotEmpty() {
        for group in MuscleGroup.allCases {
            #expect(!group.localizedName.isEmpty, "MuscleGroup.\(group) has empty localizedName")
        }
    }

    @Test("All cases have non-empty sfSymbol")
    func sfSymbolNotEmpty() {
        for group in MuscleGroup.allCases {
            #expect(!group.sfSymbol.isEmpty, "MuscleGroup.\(group) has empty sfSymbol")
        }
    }

    @Test("Specific localizedName values match spec")
    func specificLocalizedNames() {
        #expect(MuscleGroup.chest.localizedName == "胸")
        #expect(MuscleGroup.back.localizedName == "背")
        #expect(MuscleGroup.shoulders.localizedName == "肩")
        #expect(MuscleGroup.legs.localizedName == "腿")
        #expect(MuscleGroup.arms.localizedName == "臂")
        #expect(MuscleGroup.core.localizedName == "核心")
        #expect(MuscleGroup.fullBody.localizedName == "全身")
    }
}

@Suite("Equipment")
struct EquipmentTests {
    @Test("All cases have non-empty localizedName")
    func localizedNameNotEmpty() {
        for equipment in Equipment.allCases {
            #expect(!equipment.localizedName.isEmpty, "Equipment.\(equipment) has empty localizedName")
        }
    }

    @Test("All cases have non-empty sfSymbol")
    func sfSymbolNotEmpty() {
        for equipment in Equipment.allCases {
            #expect(!equipment.sfSymbol.isEmpty, "Equipment.\(equipment) has empty sfSymbol")
        }
    }

    @Test("Specific localizedName values match spec")
    func specificLocalizedNames() {
        #expect(Equipment.barbell.localizedName == "杠铃")
        #expect(Equipment.dumbbell.localizedName == "哑铃")
        #expect(Equipment.machine.localizedName == "固定器械")
        #expect(Equipment.bodyweight.localizedName == "自重")
        #expect(Equipment.cable.localizedName == "绳索")
        #expect(Equipment.kettlebell.localizedName == "壶铃")
    }
}

@Suite("MuscleTranslation")
struct MuscleTranslationTests {
    static let expectedMuscles = [
        "adductors", "anterior deltoid", "biceps", "brachialis", "brachioradialis",
        "calves", "core", "erector spinae", "forearms", "glutes",
        "gluteus medius", "gluteus minimus", "hamstrings", "hip flexors",
        "infraspinatus", "lateral deltoid", "latissimus dorsi",
        "lower pectoralis major", "lower trapezius", "obliques",
        "pectoralis major", "quadriceps", "rear deltoid", "rectus abdominis",
        "rhomboids", "serratus anterior", "tibialis anterior",
        "transverse abdominis", "trapezius", "triceps",
        "upper pectoralis major", "upper trapezius",
    ]

    @Test("All 32 muscle names have translations")
    func allMusclesCovered() {
        #expect(MuscleTranslation.allMuscleNames.count == 32)
        for name in MuscleTranslationTests.expectedMuscles {
            let translation = MuscleTranslation.chineseName(for: name)
            #expect(translation != name, "\(name) has no translation (returned original)")
        }
    }

    @Test("Translations are non-empty")
    func translationsNotEmpty() {
        for (_, value) in MuscleTranslation.allMuscleNames {
            #expect(!value.isEmpty)
        }
    }

    @Test("Lookup is case-insensitive")
    func caseInsensitiveLookup() {
        #expect(MuscleTranslation.chineseName(for: "Biceps") == "肱二头肌")
        #expect(MuscleTranslation.chineseName(for: "QUADRICEPS") == "股四头肌")
    }

    @Test("Unknown muscle name returns original")
    func unknownMuscleReturnsOriginal() {
        #expect(MuscleTranslation.chineseName(for: "unknown_muscle") == "unknown_muscle")
    }

    @Test("Specific translations match spec")
    func specificTranslations() {
        #expect(MuscleTranslation.chineseName(for: "pectoralis major") == "胸大肌")
        #expect(MuscleTranslation.chineseName(for: "latissimus dorsi") == "背阔肌")
        #expect(MuscleTranslation.chineseName(for: "triceps") == "肱三头肌")
    }
}
