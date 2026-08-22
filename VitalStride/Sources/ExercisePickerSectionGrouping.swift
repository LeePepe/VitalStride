import Foundation
import VitalModels

enum ExercisePickerSectionGrouping {
    static func groupedSections(
        from exercises: [Exercise],
        muscleGroup: MuscleGroup? = nil,
        searchText: String = ""
    ) -> [(ExerciseSection, [Exercise])] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSearch = !trimmed.isEmpty

        var buckets: [ExerciseSection: [Exercise]] = [:]
        buckets.reserveCapacity(ExerciseSection.allCases.count)

        for exercise in exercises {
            if let selectedMuscleGroup = muscleGroup, exercise.muscleGroup != selectedMuscleGroup {
                continue
            }

            if hasSearch {
                let matchesSearch =
                    exercise.nameEn.localizedCaseInsensitiveContains(trimmed) ||
                    exercise.nameZh.localizedCaseInsensitiveContains(trimmed)
                if !matchesSearch {
                    continue
                }
            }

            buckets[exercise.section, default: []].append(exercise)
        }

        return ExerciseSection.allCases.compactMap { section in
            guard let items = buckets[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }
}
