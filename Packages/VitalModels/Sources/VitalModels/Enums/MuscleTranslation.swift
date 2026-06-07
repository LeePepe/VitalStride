import Foundation

public enum MuscleTranslation {
    private static let mapping: [String: String] = [
        "anterior deltoid": "三角肌前束",
        "biceps": "肱二头肌",
        "brachialis": "肱肌",
        "calves": "小腿",
        "erector spinae": "竖脊肌",
        "forearms": "前臂",
        "glutes": "臀肌",
        "hamstrings": "腘绳肌",
        "hip flexors": "髋屈肌",
        "infraspinatus": "冈下肌",
        "lateral deltoid": "三角肌中束",
        "latissimus dorsi": "背阔肌",
        "lower pectoralis major": "胸大肌下部",
        "obliques": "腹斜肌",
        "pectoralis major": "胸大肌",
        "quadriceps": "股四头肌",
        "rear deltoid": "三角肌后束",
        "rectus abdominis": "腹直肌",
        "rhomboids": "菱形肌",
        "serratus anterior": "前锯肌",
        "tibialis anterior": "胫骨前肌",
        "transverse abdominis": "腹横肌",
        "trapezius": "斜方肌",
        "triceps": "肱三头肌",
        "upper pectoralis major": "胸大肌上部",
        "upper trapezius": "上斜方肌",
    ]

    public static func chineseName(for englishName: String) -> String {
        mapping[englishName.lowercased()] ?? englishName
    }

    public static var allMuscleNames: [String: String] { mapping }
}
