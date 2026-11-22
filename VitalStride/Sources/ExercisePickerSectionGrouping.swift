import Foundation
import SwiftData
import VitalModels

struct ExercisePickerCardSnapshot: Identifiable, Equatable, Sendable {
    let id: PersistentIdentifier
    let nameEn: String
    let nameZh: String
    let localizedName: String
    let muscleGroup: MuscleGroup
    let muscleLocalizedName: String
    let equipment: Equipment
    let equipmentLocalizedName: String
    let section: ExerciseSection
    let isCustom: Bool
    let mediaKey: String?

    init(exercise: Exercise) {
        self.id = exercise.persistentModelID
        self.nameEn = exercise.nameEn
        self.nameZh = exercise.nameZh
        self.localizedName = exercise.localizedName
        self.muscleGroup = exercise.muscleGroup
        self.muscleLocalizedName = exercise.muscleGroup.localizedName
        self.equipment = exercise.equipment
        self.equipmentLocalizedName = exercise.equipment.localizedName
        self.section = exercise.section
        self.isCustom = exercise.isCustom
        self.mediaKey = exercise.mediaKey
    }
}

enum ExercisePickerSectionGrouping {
    static func makeSnapshots(from exercises: [Exercise]) -> [ExercisePickerCardSnapshot] {
        exercises.map(ExercisePickerCardSnapshot.init(exercise:))
    }

    static func groupedSnapshotSections(
        from snapshots: [ExercisePickerCardSnapshot],
        muscleGroup: MuscleGroup? = nil,
        searchText: String = ""
    ) -> [(ExerciseSection, [ExercisePickerCardSnapshot])] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSearch = !trimmed.isEmpty

        var buckets: [ExerciseSection: [ExercisePickerCardSnapshot]] = [:]
        buckets.reserveCapacity(ExerciseSection.allCases.count)

        for snapshot in snapshots {
            if let selectedMuscleGroup = muscleGroup, snapshot.muscleGroup != selectedMuscleGroup {
                continue
            }

            if hasSearch {
                let matchesSearch =
                    snapshot.nameEn.localizedCaseInsensitiveContains(trimmed) ||
                    snapshot.nameZh.localizedCaseInsensitiveContains(trimmed)
                if !matchesSearch {
                    continue
                }
            }

            buckets[snapshot.section, default: []].append(snapshot)
        }

        return ExerciseSection.allCases.compactMap { section in
            guard let items = buckets[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }

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

    /// Scrubbing clamps beyond either end, including drags outside the rail.
    static func indexSection(at y: CGFloat, height: CGFloat, sections: [ExerciseSection]) -> ExerciseSection? {
        guard !sections.isEmpty, height > 0, y.isFinite, height.isFinite else { return nil }
        let fraction = min(max(y / height, 0), 1)
        let index = min(Int(fraction * CGFloat(sections.count)), sections.count - 1)
        return sections[index]
    }

    /// Explicit, localized one-character markers avoid ambiguous English initials.
    static func indexCharacter(for section: ExerciseSection) -> String {
        switch section {
        case .assisted: String(localized: "picker.index.assisted", comment: "One-character assisted index marker")
        case .band: String(localized: "picker.index.band", comment: "One-character band index marker")
        case .barbell: String(localized: "picker.index.barbell", comment: "One-character barbell index marker")
        case .bodyweight: String(localized: "picker.index.bodyweight", comment: "One-character bodyweight index marker")
        case .cable: String(localized: "picker.index.cable", comment: "One-character cable index marker")
        case .dumbbell: String(localized: "picker.index.dumbbell", comment: "One-character dumbbell index marker")
        case .ezBarbell: String(localized: "picker.index.ezBarbell", comment: "One-character ezBarbell index marker")
        case .kettlebell: String(localized: "picker.index.kettlebell", comment: "One-character kettlebell index marker")
        case .leverageMachine: String(localized: "picker.index.leverageMachine", comment: "One-character leverageMachine index marker")
        case .machine: String(localized: "picker.index.machine", comment: "One-character machine index marker")
        case .medicineBall: String(localized: "picker.index.medicineBall", comment: "One-character medicineBall index marker")
        case .rope: String(localized: "picker.index.rope", comment: "One-character rope index marker")
        case .sledMachine: String(localized: "picker.index.sledMachine", comment: "One-character sledMachine index marker")
        case .smithMachine: String(localized: "picker.index.smithMachine", comment: "One-character smithMachine index marker")
        case .stabilityBall: String(localized: "picker.index.stabilityBall", comment: "One-character stabilityBall index marker")
        case .weighted: String(localized: "picker.index.weighted", comment: "One-character weighted index marker")
        case .other: String(localized: "picker.index.other", comment: "One-character other index marker")
        }
    }
}
