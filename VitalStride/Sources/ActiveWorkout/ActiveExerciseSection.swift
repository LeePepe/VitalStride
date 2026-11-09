// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftData
import SwiftUI
import VitalModels
import VitalUI

struct CascadeDeletionRequest: Identifiable {
    let exerciseSet: ExerciseSet
    let setNumber: Int
    let childCount: Int
    let childKind: SubSetChildKind

    var id: PersistentIdentifier { exerciseSet.persistentModelID }
}

struct ActiveExerciseSectionInteraction: Sendable {
    typealias ToggleAction = @MainActor @Sendable () -> Void

    var registerToggle: @MainActor @Sendable (AnyHashable, @escaping ToggleAction) -> Void
    var onCollapseChange: @MainActor @Sendable (AnyHashable, Bool) -> Void

    init(
        registerToggle: @escaping @MainActor @Sendable (AnyHashable, @escaping ToggleAction) -> Void = { _, _ in },
        onCollapseChange: @escaping @MainActor @Sendable (AnyHashable, Bool) -> Void = { _, _ in }
    ) {
        self.registerToggle = registerToggle
        self.onCollapseChange = onCollapseChange
    }
}

private struct ActiveExerciseSectionInteractionKey: EnvironmentKey {
    static let defaultValue = ActiveExerciseSectionInteraction()
}

extension EnvironmentValues {
    var activeExerciseSectionInteraction: ActiveExerciseSectionInteraction {
        get { self[ActiveExerciseSectionInteractionKey.self] }
        set { self[ActiveExerciseSectionInteractionKey.self] = newValue }
    }
}

struct ActiveExerciseSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @Environment(\.activeExerciseSectionInteraction) private var interaction
    @Environment(\.modelContext) private var modelContext
    @AppStorage("weightUnit") private var weightUnit: WeightUnit = .kg

    let workoutExercise: WorkoutExercise
    let isActive: Bool
    let onActivate: () -> Void
    let onSetCompleted: (ExerciseSet) -> Void
    let onSetDeleted: () -> Void
    let onReplace: () -> Void
    let onSubstitute: () -> Void
    let onDelete: () -> Void
    let undoController: SetDeletionUndoController

    @State private var showingDeleteConfirmation = false
    @State private var pendingCascadeDeletion: CascadeDeletionRequest?
    @State private var isCollapsed = false
    @AccessibilityFocusState private var focusedRowID: PersistentIdentifier?

    private var sortedSets: [ExerciseSet] {
        (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
    }

    struct RowContext {
        let exerciseSet: ExerciseSet
        let mainSetNumber: Int
        let isLastSubSet: Bool
        let recentWeightKg: Double?
    }

    private var rowContexts: [RowContext] {
        Self.rowContexts(from: sortedSets)
    }

    private var totalSetCount: Int { sortedSets.count }
    private var completedSetCount: Int { sortedSets.filter(\.isCompleted).count }
    private var isExpanded: Bool { isActive && !isCollapsed }

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
                mainSetNumber: isSub ? max(0, mainsBefore - 1) : mainsBefore,
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
        let toggleAction: ActiveExerciseSectionInteraction.ToggleAction = {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                isCollapsed.toggle()
            }
        }
        VStack(spacing: 0) {
            exerciseHeader(toggleAction: toggleAction)
            if isExpanded {
                VStack(spacing: 0) {
                    tiledTableHeader
                    ForEach(Array(contexts.enumerated()), id: \.element.exerciseSet.persistentModelID) { offset, ctx in
                        let exerciseSet = ctx.exerciseSet
                        SwipeToDeleteSetRow(canDelete: canDelete) {
                            requestDelete(exerciseSet)
                        } content: {
                            Group {
                                if exerciseSet.setType.isSubSet {
                                    SubSetRow(
                                        exerciseSet: exerciseSet,
                                        weightUnit: weightUnit,
                                        isLast: ctx.isLastSubSet,
                                        parentSetNumber: ctx.mainSetNumber,
                                        exercise: workoutExercise.exercise,
                                        recentWeightKg: ctx.recentWeightKg,
                                        onToggleCompleted: { wasCompleted in
                                            if !wasCompleted { onSetCompleted(exerciseSet) }
                                        },
                                        onDelete: {
                                            requestDelete(exerciseSet)
                                        },
                                        onAddSubSet: { type in
                                            addSubSet(after: exerciseSet, type: type)
                                        }
                                    )
                                } else {
                                    SetRow(
                                        index: ctx.mainSetNumber,
                                        exerciseSet: exerciseSet,
                                        weightUnit: weightUnit,
                                        canDelete: canDelete,
                                        exercise: workoutExercise.exercise,
                                        recentWeightKg: ctx.recentWeightKg,
                                        onToggleCompleted: { wasCompleted in
                                            if !wasCompleted { onSetCompleted(exerciseSet) }
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
                                }
                            }
                            .accessibilityFocused($focusedRowID, equals: exerciseSet.persistentModelID)
                        }

                        if offset + 1 < contexts.count {
                            Divider()
                                .opacity(0.22)
                                .padding(.horizontal, 12)
                        }
                    }
                    cardFooter
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 14)
        .confirmationDialog(
            String(localized: "删除动作？", comment: "Delete exercise confirmation title"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "删除", comment: "Delete confirmation button"), role: .destructive) { onDelete() }
            Button(String(localized: "取消", comment: "Cancel confirmation button"), role: .cancel) {}
        } message: {
            Text(String(localized: "该动作及所有已录入的组数据将被删除", comment: "Delete exercise confirmation message"))
        }
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

    private var cascadeConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingCascadeDeletion != nil },
            set: { newValue in
                if !newValue { pendingCascadeDeletion = nil }
            }
        )
    }

    private var muscleAccentColor: Color {
        FocusAtmosphereTheme.resolve(
            muscleGroup: workoutExercise.exercise?.muscleGroup,
            stageMode: .activeSet
        ).primaryTint
    }

    private var tiledTableHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(String(localized: "组序", comment: "Set column header"))
                .frame(width: 44, alignment: .center)
            Text(String(localized: "重量 \(weightUnit.rawValue.uppercased())", comment: "Weight column header"))
                .frame(maxWidth: .infinity, alignment: .center)
            Text(String(localized: "次数", comment: "Reps column header"))
                .frame(width: 84, alignment: .center)
            Text("✓")
                .frame(width: 44, alignment: .center)
            Text(String(localized: "更多", comment: "More column header"))
                .frame(width: 40, alignment: .center)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, minHeight: 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "组序、上次、重量、次数、完成", comment: "Set table column headers"))
    }

    private var exerciseSubtitle: String? {
        guard let exercise = workoutExercise.exercise else { return nil }
        let values = [exercise.muscleGroup.localizedName, exercise.equipment.localizedName]
            .filter { !$0.isEmpty }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func exerciseHeader(
        toggleAction: @escaping ActiveExerciseSectionInteraction.ToggleAction
    ) -> some View {
        let allDone = completedSetCount == totalSetCount && totalSetCount > 0
        let stateDescription = isExpanded
            ? String(localized: "已展开", comment: "Expanded exercise section state")
            : String(localized: "已折叠", comment: "Collapsed exercise section state")
        return HStack(alignment: .center, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                    if isExpanded {
                        isCollapsed.toggle()
                    } else {
                        isCollapsed = false
                        onActivate()
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(allDone ? Color.green.opacity(0.16) : muscleAccentColor.opacity(0.16))
                            .frame(width: 34, height: 34)
                        if allDone {
                            Image(systemName: "checkmark")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.green)
                        } else {
                            Text("\(workoutExercise.order + 1)")
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(muscleAccentColor)
                        }
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(workoutExercise.exercise?.localizedName ?? String(localized: "动作", comment: "Exercise"))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        if let exerciseSubtitle {
                            Text(exerciseSubtitle)
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Text("\(completedSetCount)/\(totalSetCount)")
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(allDone ? Color.green : Color.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(
                String(
                    localized: "\(completedSetCount)/\(totalSetCount) 组，\(stateDescription)",
                    comment: "Exercise completion and expansion state"
                )
            )
            .accessibilityHint(String(localized: "轻点展开或折叠该动作", comment: "Toggle exercise section collapse"))

            exerciseActionMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54)
        .onAppear {
            isCollapsed = !isActive
            interaction.registerToggle(workoutExercise.persistentModelID, toggleAction)
        }
        .onChange(of: isActive) { _, active in
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
                isCollapsed = !active
            }
        }
        .onChange(of: completedSetCount) { _, count in
            if count < totalSetCount { isCollapsed = false }
        }
        .onChange(of: isCollapsed) { _, collapsed in
            interaction.onCollapseChange(workoutExercise.persistentModelID, collapsed)
        }
    }

    private var exerciseActionMenu: some View {
        Menu {
            Button(action: onSubstitute) {
                Label(String(localized: "active_workout.substitute.menu_title", defaultValue: "Smart Substitute", comment: "Smart substitute menu item"), systemImage: "sparkles")
            }
            Button(action: onReplace) {
                Label(String(localized: "替换动作", comment: "Replace exercise menu item"), systemImage: "arrow.triangle.2.circlepath")
            }
            Divider()
            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label(String(localized: "删除动作", comment: "Delete exercise menu item"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .frame(width: 40, height: 44, alignment: .center)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "动作操作菜单", comment: "Exercise action menu a11y label"))
    }

    private var cardFooter: some View {
        Button(action: addSet) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                Text(String(localized: "添加一组", comment: "Add set button"))
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(AddSetButtonStyle())
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityLabel(String(localized: "添加一组", comment: "Add set button a11y"))
        .accessibilityHint(String(localized: "在列表末尾插入新的一组", comment: "Add set hint"))
        .accessibilityIdentifier("workout_section_add_set_\(workoutExercise.order)")
    }

    nonisolated static func appendedMainSet(in workoutExercise: WorkoutExercise) -> ExerciseSet {
        let sortedSets = (workoutExercise.sets ?? []).sorted { $0.order < $1.order }
        let lastMainSet = sortedSets.last(where: { !$0.setType.isSubSet })
        let order = sortedSets.count
        return ExerciseSet(
            order: order,
            weight: lastMainSet?.weight ?? 0,
            reps: lastMainSet?.reps ?? 0,
            setType: lastMainSet?.setType ?? .working,
            isUnilateral: lastMainSet?.isUnilateral ?? false,
            weightRight: lastMainSet?.weightRight
        )
    }

    nonisolated static func insertAppendedMainSet(
        in workoutExercise: WorkoutExercise,
        using modelContext: ModelContext
    ) -> ExerciseSet {
        let newSet = Self.appendedMainSet(in: workoutExercise)
        newSet.workoutExercise = workoutExercise
        modelContext.insert(newSet)
        return newSet
    }

    private func addSet() {
        isCollapsed = false
        _ = Self.insertAppendedMainSet(in: workoutExercise, using: modelContext)
    }

    private func addSubSet(after parentSet: ExerciseSet, type: SetType) {
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.30, dampingFraction: 0.85)) {
            _ = WorkoutDualModeEngine.insertSubSet(after: parentSet, type: type, in: workoutExercise, using: modelContext)
        }
    }

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

    private func performDelete(_ exerciseSet: ExerciseSet) {
        let contexts = rowContexts
        let targets = WorkoutSetTree.deletionTargets(for: exerciseSet, in: workoutExercise)
        let targetIDs = Set(targets.map(\.persistentModelID))
        let snapshots = SetDeletionUndo.snapshots(for: targets, in: workoutExercise)
        let isSubSet = exerciseSet.setType.isSubSet
        let setNumber = displaySetNumber(of: exerciseSet)
        let setType = exerciseSet.setType

        let deletedIndices = Set(contexts.indices.filter {
            targetIDs.contains(contexts[$0].exerciseSet.persistentModelID)
        })
        let focusTarget = SetDeletionFocusTarget.focusIndexAfterDeletion(
            deleting: deletedIndices,
            isSubSet: contexts.map { $0.exerciseSet.setType.isSubSet }
        ).map { contexts[$0].exerciseSet.persistentModelID }

        var didDelete = false
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.30, dampingFraction: 0.85)) {
            didDelete = WorkoutSetManager.deleteSet(exerciseSet, from: workoutExercise, using: modelContext)
        }
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
        focusedRowID = focusTarget
        onSetDeleted()
    }

    private func displaySetNumber(of exerciseSet: ExerciseSet) -> Int {
        guard let ctx = rowContexts.first(where: {
            $0.exerciseSet.persistentModelID == exerciseSet.persistentModelID
        }) else { return 1 }
        return exerciseSet.setType.isSubSet ? ctx.mainSetNumber : ctx.mainSetNumber + 1
    }

    private func copyToNext(from source: ExerciseSet) {
        Self.copyToNext(from: source, in: workoutExercise, using: modelContext)
    }

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

struct SwipeToDeleteSetRow<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let canDelete: Bool
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offsetX: CGFloat = 0
    @State private var isRevealed = false

    private let revealWidth: CGFloat = 72
    private let revealThreshold: CGFloat = 40
    private let fullSwipeThreshold: CGFloat = 140

    var body: some View {
        ZStack(alignment: .trailing) {
            if canDelete && (offsetX < 0 || isRevealed) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84)) {
                        offsetX = 0
                        isRevealed = false
                    }
                    onDelete()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "trash.fill")
                            .font(.caption.weight(.bold))
                        Text(String(localized: "删除", comment: "Delete swipe action"))
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.white)
                    .frame(width: max(revealWidth, -offsetX))
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "删除本组", comment: "Delete set menu item"))
            }

            content()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .offset(x: canDelete ? offsetX : 0)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onChanged { value in
                    guard canDelete else { return }
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let base = isRevealed ? -revealWidth : 0
                    let proposed = base + value.translation.width
                    offsetX = min(0, max(-180, proposed))
                }
                .onEnded { value in
                    guard canDelete else { return }
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    let base = isRevealed ? -revealWidth : 0
                    let finalOffset = base + value.translation.width
                    withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.84)) {
                        if finalOffset < -fullSwipeThreshold {
                            offsetX = 0
                            isRevealed = false
                            onDelete()
                        } else if finalOffset < -revealThreshold {
                            offsetX = -revealWidth
                            isRevealed = true
                        } else {
                            offsetX = 0
                            isRevealed = false
                        }
                    }
                }
        )
    }
}

private struct AddSetButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.98 : 1.0))
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
