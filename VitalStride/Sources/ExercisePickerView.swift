// swiftlint:disable no_hardcoded_chinese
import DesignKit
import os
import SwiftData
import SwiftUI
import VitalModels
#if canImport(UIKit)
import UIKit
#endif

private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "ExercisePicker")

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Exercise.nameEn) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var selectedExercises: [Exercise] = []
    @State private var visibleEquipment: Equipment?
    @State private var draggedEquipment: Equipment?
    @State private var cachedEquipmentGroups: [(Equipment, [Exercise])]?
    let selectionMode: SelectionMode

    private static let searchDebounceNanoseconds: UInt64 = 200_000_000

    enum SelectionMode {
        case single(onSelect: (Exercise) -> Void)
        case multiple(onConfirm: ([Exercise]) -> Void)
    }

    init(
        initialMuscleGroup: MuscleGroup? = nil,
        onSelect: @escaping (Exercise) -> Void
    ) {
        self.selectionMode = .single(onSelect: onSelect)
        self._selectedMuscleGroup = State(initialValue: initialMuscleGroup)
    }

    init(onConfirm: @escaping ([Exercise]) -> Void) {
        self.selectionMode = .multiple(onConfirm: onConfirm)
    }

    private var isMultiSelect: Bool {
        if case .multiple = selectionMode { return true }
        return false
    }

    private var equipmentGroups: [(Equipment, [Exercise])] {
        cachedEquipmentGroups ?? Self.computeEquipmentGroups(
            from: exercises,
            muscleGroup: selectedMuscleGroup,
            searchText: debouncedSearchText
        )
    }

    static nonisolated func computeEquipmentGroups(
        from exercises: [Exercise],
        muscleGroup: MuscleGroup?,
        searchText: String
    ) -> [(Equipment, [Exercise])] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSearch = !trimmed.isEmpty
        var buckets: [Equipment: [Exercise]] = [:]
        buckets.reserveCapacity(Equipment.allCases.count)

        for exercise in exercises {
            if let group = muscleGroup, exercise.muscleGroup != group { continue }
            if hasSearch {
                let matches = exercise.nameEn.localizedCaseInsensitiveContains(trimmed) ||
                    exercise.nameZh.localizedCaseInsensitiveContains(trimmed)
                if !matches { continue }
            }
            buckets[exercise.equipment, default: []].append(exercise)
        }

        return Equipment.allCases.compactMap { equipment in
            guard let items = buckets[equipment], !items.isEmpty else { return nil }
            return (equipment, items)
        }
    }

    private var gridColumns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ContentUnavailableView(
                        String(localized: "动作库为空", comment: "Empty exercise library title"),
                        systemImage: "tray",
                        description: Text(String(localized: "请先导入预置动作库", comment: "Empty exercise library description"))
                    )
                } else {
                    VStack(spacing: 0) {
                        exerciseCardGrid
                            .frame(maxWidth: .infinity)
                        muscleGroupFilterBar
                    }
                }
            }
            .searchable(text: $searchText, prompt: String(localized: "搜索动作", comment: "Exercise search prompt"))
            .navigationTitle(String(localized: "选择动作", comment: "Exercise picker navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", comment: "Cancel button")) { dismiss() }
                }
                if isMultiSelect {
                    ToolbarItem(placement: .confirmationAction) {
                        confirmButton
                    }
                }
            }
            .onAppear {
                if cachedEquipmentGroups == nil {
                    cachedEquipmentGroups = Self.computeEquipmentGroups(
                        from: exercises,
                        muscleGroup: selectedMuscleGroup,
                        searchText: debouncedSearchText
                    )
                }
            }
            .onChange(of: exercises) { _, newExercises in
                cachedEquipmentGroups = Self.computeEquipmentGroups(
                    from: newExercises,
                    muscleGroup: selectedMuscleGroup,
                    searchText: debouncedSearchText
                )
            }
            .onChange(of: selectedMuscleGroup) { _, newGroup in
                let newGroups = Self.computeEquipmentGroups(
                    from: exercises,
                    muscleGroup: newGroup,
                    searchText: debouncedSearchText
                )
                cachedEquipmentGroups = newGroups
                // Unconditionally reset scroll to top when muscle group changes,
                // even if the new list still contains the current visibleEquipment
                // (e.g. both "全部" and "胸部" have "哑铃"). Otherwise the ScrollView
                // keeps the old offset and shows blank space at the bottom (MY-1250).
                visibleEquipment = newGroups.first?.0
            }
            .onChange(of: debouncedSearchText) { _, newText in
                let newGroups = Self.computeEquipmentGroups(
                    from: exercises,
                    muscleGroup: selectedMuscleGroup,
                    searchText: newText
                )
                cachedEquipmentGroups = newGroups
                // Same reasoning as muscle-group change: search-driven content
                // shrinks can strand the scroll offset past the new content end.
                visibleEquipment = newGroups.first?.0
            }
            .task(id: searchText) {
                let pending = searchText
                if pending == debouncedSearchText { return }
                try? await Task.sleep(nanoseconds: Self.searchDebounceNanoseconds)
                if Task.isCancelled { return }
                debouncedSearchText = pending
            }
        }
    }

    @ViewBuilder
    private var confirmButton: some View {
        let count = selectedIDs.count
        Button {
            if case .multiple(let onConfirm) = selectionMode {
                signposter.emitEvent("exercise_picker_confirm", "count=\(count)")
                onConfirm(selectedExercises)
                dismiss()
            }
        } label: {
            Text(String(localized: "添加 (\(count))", comment: "Confirm multi-select button with count"))
        }
        .disabled(count == 0)
        .accessibilityLabel(String(localized: "添加 \(count) 个动作", comment: "Confirm multi-select a11y label"))
    }

    // MARK: - Muscle Group Filter Bar (bottom)

    private var muscleGroupFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                muscleChip(
                    label: String(localized: "全部", comment: "All muscle groups filter chip label"),
                    isSelected: selectedMuscleGroup == nil
                ) {
                    selectedMuscleGroup = nil
                }

                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    muscleChip(
                        label: group.localizedName,
                        isSelected: selectedMuscleGroup == group
                    ) {
                        selectedMuscleGroup = group
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .liquidGlassBar(theme: theme, cornerRadius: 0)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.neutrals.border).frame(height: 1)
        }
    }

    private func muscleChip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(TypeScale.meta)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? theme.primary.onPrimary : theme.neutrals.text2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? theme.primary.primary : theme.neutrals.inner)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Card Grid
    //
    // Horizontal insets are kept stable regardless of index-bar visibility so
    // that switching muscle groups between multi-section and single-section
    // states does not reflow `LazyVGrid` column widths (MY-1251). The trailing
    // reserve equals the space the index bar physically occupies
    // (`EquipmentIndexBar.hitWidth` + its trailing padding) and is applied
    // whether or not the bar is currently rendered.
    static let cardGridHorizontalInset: CGFloat = 16
    static let cardGridVerticalInset: CGFloat = 16
    static let cardGridIndexBarReserve: CGFloat = EquipmentIndexBar.hitWidth + 4

    @ViewBuilder
    private var exerciseCardGrid: some View {
        if equipmentGroups.isEmpty {
            emptyState
        } else {
            let equipments = equipmentGroups.map { $0.0 }
            let showsIndexBar = equipments.count >= 2
            ScrollViewReader { gridProxy in
                ZStack(alignment: .trailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(equipmentGroups, id: \.0) { equipment, items in
                                equipmentSection(equipment: equipment, exercises: items)
                                    .id(equipment)
                            }
                        }
                        .padding(.vertical, Self.cardGridVerticalInset)
                        .padding(.leading, Self.cardGridHorizontalInset)
                        .padding(.trailing, Self.cardGridHorizontalInset + Self.cardGridIndexBarReserve)
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $visibleEquipment, anchor: .top)

                    if showsIndexBar {
                        EquipmentIndexBar(
                            equipments: equipments,
                            activeEquipment: visibleEquipment ?? draggedEquipment,
                            onSelect: { equipment in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    gridProxy.scrollTo(equipment, anchor: .top)
                                }
                            },
                            onDragChanged: { equipment in
                                draggedEquipment = equipment
                            },
                            onDragEnded: {
                                draggedEquipment = nil
                            }
                        )
                        .padding(.trailing, 4)
                        .padding(.vertical, 16)
                    }
                }
                .overlay(alignment: .center) {
                    if let dragged = draggedEquipment {
                        sectionPreviewPopup(equipment: dragged)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: draggedEquipment)
                .onChange(of: equipmentGroups.map(\.0)) { _, newEquipments in
                    if let current = visibleEquipment, !newEquipments.contains(current) {
                        visibleEquipment = newEquipments.first
                    } else if visibleEquipment == nil {
                        visibleEquipment = newEquipments.first
                    }
                }
            }
        }
    }

    private func sectionPreviewPopup(equipment: Equipment) -> some View {
        VStack(spacing: 8) {
            Image(systemName: equipment.sfSymbol)
                .font(.system(size: 48, weight: .light))
            Text(equipment.localizedName)
                .font(.title3)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(minWidth: 140, minHeight: 140)
        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !debouncedSearchText.isEmpty {
            ContentUnavailableView.search(text: debouncedSearchText)
        } else if let group = selectedMuscleGroup {
            ContentUnavailableView(
                String(localized: "没有动作", comment: "No exercises found title"),
                systemImage: "dumbbell",
                description: Text(String(localized: "\(group.localizedName)分类下暂无动作", comment: "No exercises in muscle group description"))
            )
        } else {
            ContentUnavailableView(
                String(localized: "没有动作", comment: "No exercises found title"),
                systemImage: "dumbbell",
                description: Text(String(localized: "暂无可用动作", comment: "No exercises available description"))
            )
        }
    }

    private func equipmentSection(equipment: Equipment, exercises: [Exercise]) -> some View {
        let color = categoryColor(categoryColorIndex(for: equipment), theme: theme)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: equipment.sfSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                Text(equipment.localizedName.uppercased())
                    .font(TypeScale.meta)
                    .fontWeight(.bold)
                    .foregroundStyle(theme.neutrals.text2)
                Text("\(exercises.count)")
                    .font(TypeScale.meta.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text3)
            }

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(exercises) { exercise in
                    ExerciseCard(
                        exercise: exercise,
                        isSelected: selectedIDs.contains(exercise.persistentModelID),
                        showsSelectionIndicator: isMultiSelect
                    ) {
                        handleCardTap(exercise)
                    }
                }
            }
        }
    }

    private func handleCardTap(_ exercise: Exercise) {
        switch selectionMode {
        case .single(let onSelect):
            onSelect(exercise)
            dismiss()
        case .multiple:
            toggleSelection(exercise)
        }
    }

    private func toggleSelection(_ exercise: Exercise) {
        let id = exercise.persistentModelID
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            selectedExercises.removeAll { $0.persistentModelID == id }
        } else {
            selectedIDs.insert(id)
            selectedExercises.append(exercise)
        }
    }
}

// MARK: - Exercise Card

private struct ExerciseCard: View {
    @Environment(\.theme) private var theme
    let exercise: Exercise
    let isSelected: Bool
    let showsSelectionIndicator: Bool
    let onTap: () -> Void

    private var equipmentColor: Color {
        categoryColor(categoryColorIndex(for: exercise.equipment), theme: theme)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: exercise.equipment.sfSymbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(equipmentColor)
                        .frame(width: 34, height: 34)
                        .background(equipmentColor.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    Spacer(minLength: 0)
                    if showsSelectionIndicator {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? theme.primary.primary : theme.neutrals.text3)
                            .accessibilityHidden(true)
                    }
                }

                mediaPreview

                Text(exercise.localizedName)
                    .font(TypeScale.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.neutrals.text1)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                muscleTag
            }
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .padding(12)
            .background(theme.neutrals.card)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(
                        isSelected ? theme.primary.primary : theme.neutrals.border,
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var muscleTag: some View {
        if let muscle = exercise.primaryMuscles.first {
            Text(MuscleTranslation.chineseName(for: muscle))
                .font(TypeScale.meta)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(theme.neutrals.inner)
                .foregroundStyle(theme.neutrals.text2)
                .clipShape(Capsule())
        }
    }

    // Media display point reserved for future authorized media assets. When
    // `mediaKey` is nil (the current default for every seeded exercise), the
    // ViewBuilder returns nothing — no placeholder frame, no image fetch.
    @ViewBuilder
    private var mediaPreview: some View {
        if exercise.mediaKey != nil {
            EmptyView()
        }
    }
}

// MARK: - Equipment Index Bar

private struct EquipmentIndexBar: View {
    @Environment(\.theme) private var theme
    let equipments: [Equipment]
    let activeEquipment: Equipment?
    let onSelect: (Equipment) -> Void
    let onDragChanged: (Equipment) -> Void
    let onDragEnded: () -> Void

    private static let verticalPadding: CGFloat = 8
    private static let barWidth: CGFloat = 28
    // Constitution §H: interactive hit targets must be at least 44pt.
    static let hitWidth: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                VStack(spacing: 2) {
                    ForEach(equipments, id: \.self) { equipment in
                        let active = activeEquipment == equipment
                        Image(systemName: equipment.sfSymbol)
                            .font(.system(size: 11, weight: active ? .bold : .medium))
                            .frame(width: 22, height: 22)
                            .foregroundStyle(active ? theme.primary.onPrimary : theme.neutrals.text2)
                            .background(active ? theme.primary.primary : Color.clear)
                            .clipShape(Circle())
                            .accessibilityLabel(equipment.localizedName)
                    }
                }
                .frame(width: Self.barWidth)
                .padding(.vertical, Self.verticalPadding)
                .liquidGlassCapsule(theme: theme)
            }
            .frame(width: Self.hitWidth, alignment: .trailing)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard let equipment = equipmentAt(
                            y: value.location.y,
                            totalHeight: geo.size.height
                        ) else { return }
                        if equipment != activeEquipment {
                            onSelect(equipment)
                            triggerSelectionHaptic()
                        }
                        onDragChanged(equipment)
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "器械分区索引", comment: "Equipment section index bar a11y label"))
        }
        .frame(width: Self.hitWidth)
    }

    private func equipmentAt(y: CGFloat, totalHeight: CGFloat) -> Equipment? {
        guard !equipments.isEmpty else { return nil }
        let usable = max(totalHeight - Self.verticalPadding * 2, 1)
        let clamped = min(max(y - Self.verticalPadding, 0), usable - 0.001)
        let rowHeight = usable / CGFloat(equipments.count)
        let index = Int(clamped / rowHeight)
        let bounded = min(max(index, 0), equipments.count - 1)
        return equipments[bounded]
    }

    private func triggerSelectionHaptic() {
        #if canImport(UIKit) && !os(watchOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}
