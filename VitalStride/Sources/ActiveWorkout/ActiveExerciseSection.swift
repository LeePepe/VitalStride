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

/// MY-1420: a main-set delete parked behind the cascade confirmation, carrying
/// the resolved child count / kind so the dialog message can name exactly what
/// disappears alongside the row the user acted on.
struct CascadeDeletionRequest: Identifiable {
    let exerciseSet: ExerciseSet
    let setNumber: Int
    let childCount: Int
    let childKind: SubSetChildKind

    var id: PersistentIdentifier { exerciseSet.persistentModelID }
}

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
    /// MY-1420: shared undo state. Owned by `ActiveWorkoutView` so a single
    /// snackbar arbitrates across every exercise section — a delete in one
    /// section must replace (not stack on) a pending undo from another.
    let undoController: SetDeletionUndoController
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg
    // MY-1091: header font ramps up in Large Mode (`.title2` vs `.headline`)
    // so the currently-worked exercise name is legible from a rack step away.
    @AppStorage("activeWorkoutLargeMode") private var largeMode = false
    @State private var showingDeleteConfirmation = false
    /// MY-1420: the main set awaiting cascade confirmation, plus the resolved
    /// child count / kind so the message names the real consequence.
    @State private var pendingCascadeDeletion: CascadeDeletionRequest?
    /// MY-1420: VoiceOver focus target. Deleting the focused row drops focus
    /// silently, so it is moved explicitly to the parent main set (for a
    /// sub-set) or the nearest surviving row.
    @AccessibilityFocusState private var focusedRowID: PersistentIdentifier?

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
                        },
                        onDelete: {
                            requestDelete(exerciseSet)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .accessibilityFocused($focusedRowID, equals: exerciseSet.persistentModelID)
                    // MY-1420: sub-sets get the same trailing full swipe as
                    // main sets. Sub-sets are always deletable — removing one
                    // can never empty the exercise (a sub-set only exists
                    // after a main set), and `WorkoutSetManager.deleteSet`'s
                    // guard stays the single source of that rule, so no count
                    // logic is duplicated here.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            requestDelete(exerciseSet)
                        } label: {
                            Label(String(localized: "删除", comment: ""), systemImage: "trash")
                        }
                    }
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
                            requestDelete(exerciseSet)
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
                    .accessibilityFocused($focusedRowID, equals: exerciseSet.persistentModelID)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if canDelete {
                            Button(role: .destructive) {
                                requestDelete(exerciseSet)
                            } label: {
                                Label(String(localized: "删除", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }
            }
            addSetButton
        } header: {
            HStack {
                Text(workoutExercise.exercise?.localizedName ?? String(localized: "动作", comment: ""))
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
            // MY-1420: cascade confirmation for a main set that owns sub-sets.
            // The swiped row says "第 3 组" but the delete also consumes the
            // sub-set run beneath it — a consequence the row cannot show, so
            // it is the one single-set deletion that earns a dialog. Main sets
            // without children keep deleting straight through (no regression
            // on the fast path).
            .confirmationDialog(
                pendingCascadeDeletion.map { SetDeletionPolicy.confirmTitle(setNumber: $0.setNumber) } ?? "",
                isPresented: cascadeConfirmationPresented,
                titleVisibility: .visible,
                presenting: pendingCascadeDeletion
            ) { request in
                Button(
                    String(localized: "删除", comment: "Delete confirmation button"),
                    role: .destructive
                ) {
                    performDelete(request.exerciseSet)
                }
                Button(String(localized: "取消", comment: "Cancel confirmation button"), role: .cancel) {}
            } message: { request in
                Text(SetDeletionPolicy.confirmMessage(
                    childCount: request.childCount,
                    kind: request.childKind
                ))
            }
        }
    }

    /// MY-1420: `confirmationDialog(_:isPresented:presenting:)` needs a Bool
    /// binding; the request itself is the source of truth so dismissing the
    /// dialog (cancel, swipe-away) clears it.
    private var cascadeConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingCascadeDeletion != nil },
            set: { newValue in
                if !newValue { pendingCascadeDeletion = nil }
            }
        )
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

    // MY-1348 (spec 017): visual redesign — subtle-fill inline button.
    // Direction (a) from the spec: `theme.primary.primarySubtle` background
    // + `Radius.inner` (10pt) rounded corner + `theme.primary.primaryText`
    // foreground + `plus.circle.fill` icon at `theme.primary.primary`.
    // Frozen contract preserved: `addSet()` on tap, a11y label + hint
    // strings unchanged, hit target raised 36 → 44pt (HIG floor).
    // Interaction feedback delivered via `AddSetButtonStyle` (opacity +
    // scale on press) since `.borderless` had no pressed state and read
    // as flat/data-row.
    private var addSetButton: some View {
        Button {
            addSet()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(theme.primary.primary)
                Text(String(localized: "添加一组", comment: ""))
                    .foregroundStyle(theme.primary.primaryText)
            }
            .font(.callout.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, largeMode ? 10 : 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.inner)
                    .fill(theme.primary.primarySubtle)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.inner))
        }
        .buttonStyle(AddSetButtonStyle())
        // MY-1348: subtle-fill chip needs its own visual band separated from
        // SetRow data rows. Bump vertical padding slightly in Large Mode; in
        // normal mode keep the row visually compact so the section rhythm
        // established by MY-1263 (D2) is preserved.
        .listRowInsets(EdgeInsets(top: largeMode ? 6 : 4, leading: 16, bottom: largeMode ? 6 : 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
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

    /// MY-1420: entry point for every delete affordance (swipe + menu, main
    /// row + sub-set row). Routes through `SetDeletionPolicy` so the confirm
    /// vs delete-now decision lives in one testable place.
    private func requestDelete(_ exerciseSet: ExerciseSet) {
        switch SetDeletionPolicy.intent(for: exerciseSet, in: workoutExercise) {
        case .confirm(let childCount, let kind):
            pendingCascadeDeletion = CascadeDeletionRequest(
                exerciseSet: exerciseSet,
                setNumber: displaySetNumber(of: exerciseSet),
                childCount: childCount,
                childKind: kind
            )
        case .immediate:
            performDelete(exerciseSet)
        }
    }

    /// Deletes for real and arms the undo window.
    ///
    /// The snapshot is captured *before* `WorkoutSetManager.deleteSet` runs,
    /// because the manager both deletes the rows and renumbers the survivors —
    /// after it returns there is nothing left to read. The delete itself stays
    /// entirely the manager's: the min-one-set guard and the parent→sub-set
    /// cascade are never re-derived here, so the UI cannot drift from the data
    /// layer's rules (it may legitimately refuse, hence the `didDelete` gate).
    private func performDelete(_ exerciseSet: ExerciseSet) {
        let contexts = rowContexts
        let targets = WorkoutSetTree.deletionTargets(for: exerciseSet, in: workoutExercise)
        let targetIDs = Set(targets.map(\.persistentModelID))
        let snapshots = SetDeletionUndo.snapshots(for: targets)
        let isSubSet = exerciseSet.setType.isSubSet
        let setNumber = displaySetNumber(of: exerciseSet)
        let setType = exerciseSet.setType

        let deletedIndices = Set(contexts.indices.filter {
            targetIDs.contains(contexts[$0].exerciseSet.persistentModelID)
        })
        let focusTarget = WorkoutSetTree.focusIndexAfterDeletion(
            deleting: deletedIndices,
            isSubSet: contexts.map { $0.exerciseSet.setType.isSubSet }
        ).map { contexts[$0].exerciseSet.persistentModelID }

        let didDelete = WorkoutSetManager.deleteSet(exerciseSet, from: workoutExercise, using: modelContext)
        guard didDelete else { return }

        pendingCascadeDeletion = nil
        undoController.record(
            snapshots: snapshots,
            workoutExercise: workoutExercise,
            message: SetDeletionPolicy.undoMessage(
                setNumber: setNumber,
                setType: setType,
                isSubSet: isSubSet
            ),
            announcement: SetDeletionPolicy.deletionAnnouncement(
                setNumber: setNumber,
                setType: setType,
                isSubSet: isSubSet
            )
        )
        // VoiceOver focus is moved explicitly: the focused row just vanished,
        // and left alone the system either drops focus or lands it somewhere
        // unrelated.
        focusedRowID = focusTarget
        onSetDeleted()
    }

    /// 1-based display number of the main set this row belongs to — the row's
    /// own number for a main set, its parent's for a sub-set — so confirmation
    /// and undo copy match what the user sees on screen.
    ///
    /// `RowContext.mainSetNumber` counts the main sets *before* a row, so a
    /// main set needs +1 to become its displayed number (matching `SetRow`'s
    /// `index + 1`), while a sub-set's value is already its parent's displayed
    /// number (matching `SubSetRow`'s `parentSetNumber`).
    private func displaySetNumber(of exerciseSet: ExerciseSet) -> Int {
        guard let ctx = rowContexts.first(where: {
            $0.exerciseSet.persistentModelID == exerciseSet.persistentModelID
        }) else { return 1 }
        return exerciseSet.setType.isSubSet ? ctx.mainSetNumber : ctx.mainSetNumber + 1
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

// MARK: - Add-Set button style (MY-1348)

/// MY-1348 (spec 017) — pressed-state feedback for `addSetButton`.
///
/// `.borderless` gives no visual acknowledgement on tap, which made the row
/// read as another data cell. This style dims and slightly shrinks on press
/// so the button feels like a real tappable control. `Sendable` is satisfied
/// implicitly by the immutable `struct`. `private` scope keeps this style
/// bound to `ActiveExerciseSection` — no exported API.
private struct AddSetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Previews (MY-1348 spec 017 — 4-state coverage)
//
// Preview matrix required by `tasks.md` §Preview Coverage: `{normal, large}
// × {light, dark}`, each with ≥ 2 sets so the `addSetButton` sits next to
// SetRows and its visual separation from data rows is directly comparable.
// Uses the same in-memory `ModelContainerConfiguration.makeTestContainer()`
// harness as `SetRow` previews.

private struct AddSetButtonPreviewWrapper: View {
    let largeMode: Bool

    init(largeMode: Bool) {
        self.largeMode = largeMode
        UserDefaults.standard.set(largeMode, forKey: "activeWorkoutLargeMode")
    }

    var body: some View {
        // swiftlint:disable:next force_try
        let container = try! ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: String(localized: "卧推", comment: ""),
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)

        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        workoutExercise.workout = workout
        context.insert(workoutExercise)

        let set1 = ExerciseSet(order: 0, weight: 60, reps: 10, setType: .working)
        set1.workoutExercise = workoutExercise
        context.insert(set1)

        let set2 = ExerciseSet(order: 1, weight: 62.5, reps: 8, setType: .working)
        set2.workoutExercise = workoutExercise
        context.insert(set2)

        return List {
            ActiveExerciseSection(
                workoutExercise: workoutExercise,
                onSetCompleted: {},
                onSetDeleted: {},
                onReplace: {},
                onSubstitute: {},
                onDelete: {},
                undoController: SetDeletionUndoController()
            )
        }
        .listStyle(.plain)
        .modelContainer(container)
        .designThemePreview()
    }
}

#Preview("AddSetButton - Normal Light") {
    AddSetButtonPreviewWrapper(largeMode: false)
        .preferredColorScheme(.light)
}

#Preview("AddSetButton - Normal Dark") {
    AddSetButtonPreviewWrapper(largeMode: false)
        .preferredColorScheme(.dark)
}

#Preview("AddSetButton - Large Light") {
    AddSetButtonPreviewWrapper(largeMode: true)
        .preferredColorScheme(.light)
}

#Preview("AddSetButton - Large Dark") {
    AddSetButtonPreviewWrapper(largeMode: true)
        .preferredColorScheme(.dark)
}
