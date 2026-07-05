// swiftlint:disable no_hardcoded_chinese
// Active Exercise Section.
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). Pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065). No semantic change.

import SwiftData
import SwiftUI
import VitalModels
import VitalUI

struct ActiveExerciseSection: View {
    let workoutExercise: WorkoutExercise
    let onSetCompleted: () -> Void
    let onSetDeleted: () -> Void
    let onReplace: () -> Void
    let onDelete: () -> Void
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    // MY-1091: header font ramps up in Large Mode (`.title2` vs `.headline`)
    // so the currently-worked exercise name is legible from a rack step away.
    @AppStorage("activeWorkoutLargeMode") private var largeMode = false
    @State private var showingDeleteConfirmation = false

    private var sortedSets: [ExerciseSet] {
        (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
    }

    var body: some View {
        Section {
            ForEach(Array(sortedSets.enumerated()), id: \.element.persistentModelID) { index, exerciseSet in
                if exerciseSet.setType.isSubSet {
                    SubSetRow(
                        exerciseSet: exerciseSet,
                        weightUnit: weightUnit,
                        isLast: isLastSubSet(at: index),
                        parentSetNumber: parentSetNumber(for: index),
                        onToggleCompleted: { wasCompleted in
                            if !wasCompleted { onSetCompleted() }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } else {
                    SetRow(
                        index: mainSetNumber(upTo: index),
                        exerciseSet: exerciseSet,
                        weightUnit: weightUnit,
                        canDelete: sortedSets.count > 1,
                        exercise: workoutExercise.exercise,
                        recentWeightKg: recentWeightKg(before: index),
                        onToggleCompleted: { wasCompleted in
                            if !wasCompleted { onSetCompleted() }
                        },
                        onDelete: {
                            deleteSet(exerciseSet)
                        },
                        onAddSubSet: { type in
                            addSubSet(after: exerciseSet, type: type)
                        },
                        onCopyToNext: {
                            copyToNext(from: exerciseSet)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if sortedSets.count > 1 {
                            Button(role: .destructive) {
                                deleteSet(exerciseSet)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            addSetButton
        } header: {
            HStack {
                Text(workoutExercise.exercise?.localizedName ?? "动作")
                    .font(LargeWorkoutFonts.exerciseName(large: largeMode))
                    .contextMenu {
                        Button {
                            onReplace()
                        } label: {
                            // swiftlint:disable:next line_length
                            Label(String(localized: "替换动作", comment: "Replace exercise context menu item"), systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            // swiftlint:disable:next line_length
                            Label(String(localized: "删除动作", comment: "Delete exercise context menu item"), systemImage: "trash")
                        }
                    }
                    // swiftlint:disable:next line_length
                    .accessibilityHint(String(localized: "长按可替换或删除动作", comment: "Exercise section header context menu a11y hint"))
                Spacer()
                Menu {
                    Button {
                        onReplace()
                    } label: {
                        // swiftlint:disable:next line_length
                        Label(String(localized: "替换动作", comment: "Replace exercise menu item"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "删除动作", comment: "Delete exercise menu item"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "动作操作菜单", comment: "Exercise action menu a11y label"))
            }
            .confirmationDialog(
                String(localized: "删除动作？", comment: "Delete exercise confirmation title"),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                // swiftlint:disable:next line_length
                Button(String(localized: "删除", comment: "Delete confirmation button"), role: .destructive) { onDelete() }
                Button(String(localized: "取消", comment: "Cancel confirmation button"), role: .cancel) {}
            } message: {
                Text(String(localized: "该动作及所有已录入的组数据将被删除", comment: "Delete exercise confirmation message"))
            }
        }
    }

    private func mainSetNumber(upTo index: Int) -> Int {
        let sets = sortedSets
        var count = 0
        // swiftlint:disable:next identifier_name
        for i in 0..<index {
            // swiftlint:disable:next for_where
            if !sets[i].setType.isSubSet { count += 1 }
        }
        return count
    }

    private func parentSetNumber(for index: Int) -> Int {
        let sets = sortedSets
        var lastMainNumber = 0
        // swiftlint:disable:next identifier_name
        for i in 0..<index {
            // swiftlint:disable:next for_where
            if !sets[i].setType.isSubSet { lastMainNumber += 1 }
        }
        return lastMainNumber
    }

    private func isLastSubSet(at index: Int) -> Bool {
        let sets = sortedSets
        if index + 1 >= sets.count { return true }
        return !sets[index + 1].setType.isSubSet
    }

    private var addSetButton: some View {
        Button {
            addSet()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("添加一组")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
        .accessibilityLabel("添加一组")
        .accessibilityHint("在列表末尾插入新的一组")
    }

    private func addSet() {
        let lastMainSet = sortedSets.last(where: { !$0.setType.isSubSet })
        let order = workoutExercise.sets?.count ?? 0
        let newSet = ExerciseSet(
            order: order,
            weight: lastMainSet?.weight ?? 0,
            reps: lastMainSet?.reps ?? 0,
            setType: lastMainSet?.setType ?? .working,
            isUnilateral: lastMainSet?.isUnilateral ?? false,
            weightRight: lastMainSet?.weightRight
        )
        newSet.workoutExercise = workoutExercise
        modelContext.insert(newSet)
    }

    private func addSubSet(after parentSet: ExerciseSet, type: SetType) {
        let sets = sortedSets
        let parentIndex = sets.firstIndex(where: { $0.persistentModelID == parentSet.persistentModelID }) ?? 0

        var insertIndex = parentIndex + 1
        while insertIndex < sets.count && sets[insertIndex].setType.isSubSet {
            insertIndex += 1
        }

        let adjustedWeight: Double
        let adjustedWeightRight: Double?
        if type == .dropSet {
            adjustedWeight = parentSet.weight * 0.85
            adjustedWeightRight = parentSet.weightRight.map { $0 * 0.85 }
        } else {
            adjustedWeight = parentSet.weight * 1.15
            adjustedWeightRight = parentSet.weightRight.map { $0 * 1.15 }
        }

        // swiftlint:disable:next identifier_name
        for i in insertIndex..<sets.count {
            sets[i].order += 1
        }

        let newSet = ExerciseSet(
            order: insertIndex,
            weight: adjustedWeight,
            reps: parentSet.reps,
            setType: type,
            isUnilateral: parentSet.isUnilateral,
            weightRight: adjustedWeightRight
        )
        newSet.workoutExercise = workoutExercise
        modelContext.insert(newSet)
    }

    private func deleteSet(_ exerciseSet: ExerciseSet) {
        let didDelete = WorkoutSetManager.deleteSet(exerciseSet, from: workoutExercise, using: modelContext)
        guard didDelete else { return }
        onSetDeleted()
    }

    /// Most recent weight (kg) recorded for this exercise in the current
    /// workout, walking backwards from `index` and skipping sub-sets. Used to
    /// feed the keyboard's preset resolver when the exercise has no seeded
    /// default weight for the tapped bucket.
    private func recentWeightKg(before index: Int) -> Double? {
        let sets = sortedSets
        // swiftlint:disable:next identifier_name
        for i in stride(from: index - 1, through: 0, by: -1) where !sets[i].setType.isSubSet {
            let weight = sets[i].weight
            if weight > 0 { return weight }
        }
        return nil
    }

    /// MY-1073 — Copy current set to next. If a next set exists (main or sub),
    /// its weight/weightRight/reps/setType/isUnilateral are overwritten. If
    /// none exists, a new main set is appended using the same ordering rules
    /// as `addSet()`. Extracted to a static helper on this type so it can be
    /// exercised from tests without instantiating the SwiftUI view.
    private func copyToNext(from source: ExerciseSet) {
        Self.copyToNext(from: source, in: workoutExercise, using: modelContext)
    }

    /// Nonisolated so tests (and any callers off the main actor) can invoke it
    /// without hopping through `@MainActor` — SwiftData `ModelContext` /
    /// `PersistentModel` writes are safe from any actor that owns the context.
    nonisolated static func copyToNext(
        from source: ExerciseSet,
        in workoutExercise: WorkoutExercise,
        using modelContext: ModelContext
    ) {
        let sortedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        guard let sourceIndex = sortedSets.firstIndex(where: {
            $0.persistentModelID == source.persistentModelID
        }) else { return }

        let nextIndex = sourceIndex + 1
        if nextIndex < sortedSets.count {
            let target = sortedSets[nextIndex]
            target.weight = source.weight
            target.weightRight = source.weightRight
            target.reps = source.reps
            target.setType = source.setType
            target.isUnilateral = source.isUnilateral
        } else {
            let order = workoutExercise.sets?.count ?? 0
            let newSet = ExerciseSet(
                order: order,
                weight: source.weight,
                reps: source.reps,
                setType: source.setType,
                isUnilateral: source.isUnilateral,
                weightRight: source.weightRight
            )
            newSet.workoutExercise = workoutExercise
            modelContext.insert(newSet)
        }
    }
}
