import Foundation

public enum MuscleTranslation {
    /// English muscle name (lowercased) → String Catalog key. Display values live in
    /// Localizable.xcstrings (zh-Hans), so no Chinese literals appear in source.
    private static let keys: [String: String] = [
        "adductors": "muscle_trans.adductors",
        "anterior deltoid": "muscle_trans.anterior_deltoid",
        "biceps": "muscle_trans.biceps",
        "brachialis": "muscle_trans.brachialis",
        "brachioradialis": "muscle_trans.brachioradialis",
        "calves": "muscle_trans.calves",
        "core": "muscle_trans.core",
        "erector spinae": "muscle_trans.erector_spinae",
        "forearms": "muscle_trans.forearms",
        "glutes": "muscle_trans.glutes",
        "gluteus medius": "muscle_trans.gluteus_medius",
        "gluteus minimus": "muscle_trans.gluteus_minimus",
        "hamstrings": "muscle_trans.hamstrings",
        "hip flexors": "muscle_trans.hip_flexors",
        "infraspinatus": "muscle_trans.infraspinatus",
        "lateral deltoid": "muscle_trans.lateral_deltoid",
        "latissimus dorsi": "muscle_trans.latissimus_dorsi",
        "lower pectoralis major": "muscle_trans.lower_pectoralis_major",
        "lower trapezius": "muscle_trans.lower_trapezius",
        "obliques": "muscle_trans.obliques",
        "pectoralis major": "muscle_trans.pectoralis_major",
        "quadriceps": "muscle_trans.quadriceps",
        "rear deltoid": "muscle_trans.rear_deltoid",
        "rectus abdominis": "muscle_trans.rectus_abdominis",
        "rhomboids": "muscle_trans.rhomboids",
        "serratus anterior": "muscle_trans.serratus_anterior",
        "tibialis anterior": "muscle_trans.tibialis_anterior",
        "transverse abdominis": "muscle_trans.transverse_abdominis",
        "trapezius": "muscle_trans.trapezius",
        "triceps": "muscle_trans.triceps",
        "upper pectoralis major": "muscle_trans.upper_pectoralis_major",
        "upper trapezius": "muscle_trans.upper_trapezius",
    ]

    public static func chineseName(for englishName: String) -> String {
        guard let key = keys[englishName.lowercased()] else { return englishName }
        return String(localized: String.LocalizationValue(key), bundle: .module)
    }

    public static var allMuscleNames: [String: String] {
        keys.reduce(into: [String: String]()) { result, pair in
            result[pair.key] = String(localized: String.LocalizationValue(pair.value), bundle: .module)
        }
    }
}
