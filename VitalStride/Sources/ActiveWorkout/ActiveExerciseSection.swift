// swiftlint:disable no_hardcoded_chinese
// Active Exercise Section.
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). Pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065). No semantic change.

import DesignKit
import SwiftData
import SwiftUI
import VitalModels
import VitalUI

struct ActiveExerciseSection: View {
    @Environment(\.theme) private var theme
    let workoutExercise: WorkoutExercise
    let onSetCompleted: () -> Void
    let onSetDeleted: () -> Void
    let onReplace: () -> Void
    /// Smart-substitute entry point (spec 003 T013a). Wired by `ActiveWorkoutView`
    /// to open `ExerciseSubstituteSheet` for the selected workout exercise.
    let onSubstitute: () -> Void
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

    /// MY-1080 — Per-row context precomputed in a single O(n) pass over the
    /// sorted sets. Replaces the previous O(n² log n) rendering path where each
    /// row re-sorted the array and re-walked it to compute numbering. Fields
    /// mirror what `SetRow` / `SubSetRow` need per row.
    struct RowContext {
        let exerciseSet: ExerciseSet
        let mainSetNumber: Int
        let isLastSubSet: Bool
        let recentWeightKg: Double?
    }

    private var rowContexts: [RowContext] {
        Self.rowContexts(from: sortedSets)
    }

    /// Nonisolated so tests can invoke it directly with a pre-sorted array of
    /// `ExerciseSet` without instantiating the SwiftUI view. `sets` MUST already
    /// be sorted by `order` (mirrors `sortedSets`).
    nonisolated static func rowContexts(from sets: [ExerciseSet]) -> [RowContext] {
        var contexts: [RowContext] = []
        contexts.reserveCapacity(sets.count)
        var mainsBefore = 0
        var lastMainWeight: Double?
        for i in 0..<sets.count {
            let set = sets[i]
            let isSub = set.setType.isSubSet
            let isLastSub = isSub && (i + 1 >= sets.count || !sets[i + 1].setType.isSubSet)
            contexts.append(RowContext(
                exerciseSet: set,
                mainSetNumber: mainsBefore,
                isLastSubSet: isLastSub,
                recentWeightKg: lastMainWeight
            ))
            if !isSub {
                mainsBefore += 1
                if set.weight > 0 { lastMainWeight = set.weight }
            }
        }
        return contexts
    }

    var body: some View {
        let contexts = rowContexts
        let canDelete = contexts.count > 1
        return Section {
            ForEach(contexts, id: \.exerciseSet.persistentModelID) { ctx in
                let exerciseSet = ctx.exerciseSet
                if exerciseSet.setType.isSubSet {
                    SubSetRow(
                        exerciseSet: exerciseSet,
                        weightUnit: weightUnit,
                        isLast: ctx.isLastSubSet,
                        parentSetNumber: ctx.mainSetNumber,
                        onToggleCompleted: { wasCompleted in
                            if !wasCompleted { onSetCompleted() }
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } else {
                    SetRow(
                        index: ctx.mainSetNumber,
                        exerciseSet: exerciseSet,
                        weightUnit: weightUnit,
                        canDelete: canDelete,
                        exercise: workoutExercise.exercise,
                        recentWeightKg: ctx.recentWeightKg,
                        previousSet: previousMainSet(forMainIndex: ctx.mainSetNumber),
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
                    // MY-1263 (D2): compact set-row vertical spacing in normal
                    // mode brings the row visual height toward ~36pt while
                    // preserving Large Mode's existing 2pt breathing room and
                    // the row-internal ≥44pt hit targets defined by SetRow.
                    .listRowInsets(EdgeInsets(top: largeMode ? 2 : 1, leading: 16, bottom: largeMode ? 2 : 1, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if canDelete {
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
                    // MY-1263 (D2): compact semibold body header in normal mode
                    // (SwiftUI's default `List` section header uses a larger
                    // title font that dominated the visual band). Large Mode
                    // continues to use the `.title2` semibold ramp from
                    // `LargeWorkoutFonts.exerciseName(large:)` for rack-step
                    // legibility (MY-1091). Text-style-driven so Dynamic Type
                    // still scales.
                    .font(largeMode
                        ? LargeWorkoutFonts.exerciseName(large: true)
                        : Font.system(.body, design: .default).weight(.semibold))
                    .foregroundStyle(theme.neutrals.text1)
                    .contextMenu {
                        Button {
                            onSubstitute()
                        } label: {
                            // swiftlint:disable:next line_length
                            Label(String(localized: "active_workout.substitute.menu_title", defaultValue: "Smart Substitute", comment: "Smart substitute context menu item"), systemImage: "sparkles")
                        }
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
                        onSubstitute()
                    } label: {
                        // swiftlint:disable:next line_length
                        Label(String(localized: "active_workout.substitute.menu_title", defaultValue: "Smart Substitute", comment: "Smart substitute menu item"), systemImage: "sparkles")
                    }
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
                        .foregroundStyle(theme.neutrals.text2)
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

    /// MY-1169 (spec 004 T006): resolves the same-index main set from the most
    /// recent completed workout so `SetRow` can render the "上次 …" hint. Returns
    /// nil when the workout link, the exercise, or the prior history is missing.
    private func previousMainSet(forMainIndex mainSetIndex: Int) -> ExerciseSet? {
        guard let workout = workoutExercise.workout else { return nil }
        return PreviousSetLookup.previousMainSet(
            currentWorkout: workout,
            exercise: workoutExercise.exercise,
            mainSetIndex: mainSetIndex,
            in: modelContext
        )
    }

    private var addSetButton: some View {
        Button {
            addSet()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(theme.primary.primary)
                Text("添加一组")
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        // MY-1263 (D2): tighter list row insets in normal mode compact the
        // "add set" row toward the ~36pt visual density target. Large Mode
        // retains the pre-existing 2pt breathing room.
        .listRowInsets(EdgeInsets(top: largeMode ? 2 : 1, leading: 16, bottom: largeMode ? 2 : 1, trailing: 16))
        .accessibilityLabel(String(localized: "添加一组", comment: "Add set button a11y"))
        .accessibilityHint(String(localized: "在列表末尾插入新的一组", comment: "Add set hint"))
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
