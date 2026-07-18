import Foundation
import Testing
@testable import VitalModels

/// Look up the zh-Hans localized value for a key from the VitalModels resource bundle.
/// Used so tests can assert against the Chinese source-language value regardless of the
/// host machine's current locale (which controls what `String(localized:)` returns).
private func zh(_ key: String) -> String {
    guard let zhURL = Bundle.module.url(forResource: "zh-Hans", withExtension: "lproj"),
          let zhBundle = Bundle(url: zhURL) else {
        return key
    }
    return NSLocalizedString(key, tableName: nil, bundle: zhBundle, comment: "")
}

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

    @Test("Specific localizedName values match spec (zh-Hans)")
    func specificLocalizedNames() {
        #expect(zh("muscle.chest") == "胸")
        #expect(zh("muscle.back") == "背")
        #expect(zh("muscle.shoulders") == "肩")
        #expect(zh("muscle.legs") == "腿")
        #expect(zh("muscle.arms") == "臂")
        #expect(zh("muscle.core") == "核心")
        #expect(zh("muscle.fullBody") == "全身")
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

    @Test("Specific localizedName values match spec (zh-Hans)")
    func specificLocalizedNames() {
        #expect(zh("equipment.barbell") == "杠铃")
        #expect(zh("equipment.dumbbell") == "哑铃")
        #expect(zh("equipment.machine") == "固定器械")
        #expect(zh("equipment.bodyweight") == "自重")
        #expect(zh("equipment.cable") == "绳索")
        #expect(zh("equipment.kettlebell") == "壶铃")
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
        // Assert the underlying key resolves (lookup is case-insensitive at the map layer);
        // the returned value is locale-dependent, so we compare against the zh-Hans catalog.
        #expect(zh("muscle_trans.biceps") == "肱二头肌")
        #expect(zh("muscle_trans.quadriceps") == "股四头肌")
        // Case-insensitive behavior itself:
        #expect(MuscleTranslation.chineseName(for: "Biceps") == MuscleTranslation.chineseName(for: "biceps"))
        #expect(MuscleTranslation.chineseName(for: "QUADRICEPS") == MuscleTranslation.chineseName(for: "quadriceps"))
    }

    @Test("Unknown muscle name returns original")
    func unknownMuscleReturnsOriginal() {
        #expect(MuscleTranslation.chineseName(for: "unknown_muscle") == "unknown_muscle")
    }

    @Test("Specific translations match spec (zh-Hans)")
    func specificTranslations() {
        #expect(zh("muscle_trans.pectoralis_major") == "胸大肌")
        #expect(zh("muscle_trans.latissimus_dorsi") == "背阔肌")
        #expect(zh("muscle_trans.triceps") == "肱三头肌")
    }
}

