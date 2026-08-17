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

private func en(_ key: String) -> String {
    guard let enURL = Bundle.module.url(forResource: "en", withExtension: "lproj"),
          let enBundle = Bundle(url: enURL) else {
        return key
    }
    return NSLocalizedString(key, tableName: nil, bundle: enBundle, comment: "")
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
    private static let expectedRawValues: Set<String> = [
        "assisted", "band", "barbell", "bodyweight", "bosu_ball", "cable",
        "dumbbell", "elliptical_machine", "ez_barbell", "hammer", "kettlebell",
        "leverage_machine", "machine", "medicine_ball", "olympic_barbell",
        "resistance_band", "roller", "rope", "skierg_machine", "sled_machine",
        "smith_machine", "stability_ball", "stationary_bike", "stepmill_machine",
        "tire", "trap_bar", "upper_body_ergometer", "weighted", "wheel_roller",
    ]

    @Test("All 29 canonical raw values are represented")
    func canonicalRawValues() {
        #expect(Equipment.allCases.count == 29)
        #expect(Set(Equipment.allCases.map(\.rawValue)) == EquipmentTests.expectedRawValues)
    }

    @Test("Every case round-trips through Codable")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for equipment in Equipment.allCases {
            let data = try encoder.encode(equipment)
            #expect(try decoder.decode(Equipment.self, from: data) == equipment)
        }
    }

    @Test("Legacy raw values remain decodable")
    func legacyRawValuesDecode() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let legacyRawValues = ["barbell", "dumbbell", "machine", "bodyweight", "cable", "kettlebell"]

        for rawValue in legacyRawValues {
            let data = try encoder.encode(rawValue)
            #expect(try decoder.decode(Equipment.self, from: data).rawValue == rawValue)
        }
    }

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

    @Test("All new equipment keys have English and Simplified Chinese translations")
    func expandedTaxonomyTranslations() {
        let expected: [(key: String, english: String, chinese: String)] = [
            ("equipment.assisted", "Assisted", "辅助器械"),
            ("equipment.band", "Band", "弹力带"),
            ("equipment.bosu_ball", "BOSU Ball", "BOSU 平衡球"),
            ("equipment.elliptical_machine", "Elliptical Machine", "椭圆机"),
            ("equipment.ez_barbell", "EZ Barbell", "EZ 曲杆"),
            ("equipment.hammer", "Hammer", "锤"),
            ("equipment.leverage_machine", "Leverage Machine", "杠杆器械"),
            ("equipment.medicine_ball", "Medicine Ball", "药球"),
            ("equipment.olympic_barbell", "Olympic Barbell", "奥林匹克杠铃"),
            ("equipment.resistance_band", "Resistance Band", "阻力带"),
            ("equipment.roller", "Roller", "滚筒"),
            ("equipment.rope", "Rope", "训练绳"),
            ("equipment.skierg_machine", "SkiErg Machine", "滑雪测功机"),
            ("equipment.sled_machine", "Sled Machine", "雪橇机"),
            ("equipment.smith_machine", "Smith Machine", "史密斯机"),
            ("equipment.stability_ball", "Stability Ball", "健身球"),
            ("equipment.stationary_bike", "Stationary Bike", "固定自行车"),
            ("equipment.stepmill_machine", "Stepmill Machine", "踏步机"),
            ("equipment.tire", "Tire", "轮胎"),
            ("equipment.trap_bar", "Trap Bar", "六角杠铃"),
            ("equipment.upper_body_ergometer", "Upper Body Ergometer", "上肢测功机"),
            ("equipment.weighted", "Weighted", "负重"),
            ("equipment.wheel_roller", "Wheel Roller", "健腹轮"),
        ]

        for translation in expected {
            #expect(en(translation.key) == translation.english)
            #expect(zh(translation.key) == translation.chinese)
        }
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
