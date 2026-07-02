// swiftlint:disable no_hardcoded_chinese
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \Exercise.nameEn) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    @State private var selectedIDs: Set<PersistentIdentifier> = []
    @State private var selectedExercises: [Exercise] = []
    @State private var visibleEquipment: Equipment?
    @State private var draggedEquipment: Equipment?
    let selectionMode: SelectionMode

    enum SelectionMode {
        case single(onSelect: (Exercise) -> Void)
        case multiple(onConfirm: ([Exercise]) -> Void)
    }

    init(onSelect: @escaping (Exercise) -> Void) {
        self.selectionMode = .single(onSelect: onSelect)
    }

    init(onConfirm: @escaping ([Exercise]) -> Void) {
        self.selectionMode = .multiple(onConfirm: onConfirm)
    }

    private var isMultiSelect: Bool {
        if case .multiple = selectionMode { return true }
        return false
    }

    private var filteredExercises: [Exercise] {
        var result = exercises
        if let group = selectedMuscleGroup {
            result = result.filter { $0.muscleGroup == group }
        }
        if !searchText.isEmpty {
            result = result.filter { exercise in
                exercise.nameEn.localizedCaseInsensitiveContains(searchText) ||
                exercise.nameZh.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var equipmentGroups: [(Equipment, [Exercise])] {
        let dict = Dictionary(grouping: filteredExercises) { $0.equipment }
        return Equipment.allCases.compactMap { equipment in
            guard let items = dict[equipment], !items.isEmpty else { return nil }
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
                    HStack(spacing: 0) {
                        muscleGroupSidebar
                        Divider()
                        exerciseCardGrid
                            .frame(maxWidth: .infinity)
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

    // MARK: - Muscle Group Sidebar

    private var muscleGroupSidebar: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                sidebarItem(
                    icon: "square.grid.2x2",
                    label: String(localized: "全部", comment: "All muscle groups sidebar label"),
                    isSelected: selectedMuscleGroup == nil
                ) {
                    selectedMuscleGroup = nil
                }

                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    sidebarItem(
                        icon: group.sfSymbol,
                        label: group.localizedName,
                        isSelected: selectedMuscleGroup == group
                    ) {
                        selectedMuscleGroup = group
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(width: 72)
        .background(Color(.systemGroupedBackground))
    }

    private func sidebarItem(
        icon: String,
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28, height: 28)
                Text(label)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
            )
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Card Grid

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
                        .padding()
                        .padding(.trailing, showsIndexBar ? 48 : 0)
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
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: equipment.sfSymbol)
                    .foregroundStyle(.secondary)
                Text(equipment.localizedName)
                    .font(.headline)
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
    let exercise: Exercise
    let isSelected: Bool
    let showsSelectionIndicator: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: exercise.equipment.sfSymbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                Text(exercise.localizedName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                muscleTags
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.blue, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected && showsSelectionIndicator {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Color.blue)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var muscleTags: some View {
        let muscles = exercise.primaryMuscles
        if !muscles.isEmpty {
            WrappingHStack(spacing: 4) {
                ForEach(muscles, id: \.self) { muscle in
                    Text(MuscleTranslation.chineseName(for: muscle))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }
}

// MARK: - Wrapping Layout

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        guard !rows.isEmpty else { return .zero }
        let height = rows.reduce(CGFloat.zero) { total, row in
            total + row.height + (total > 0 ? spacing : 0)
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row()
        var currentWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = currentRow.indices.isEmpty ? size.width : currentWidth + spacing + size.width
            if neededWidth > maxWidth && !currentRow.indices.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
                currentWidth = 0
            }
            currentRow.indices.append(index)
            currentRow.height = max(currentRow.height, size.height)
            currentWidth = currentRow.indices.count == 1 ? size.width : currentWidth + spacing + size.width
        }
        if !currentRow.indices.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}

private struct Row {
    var indices: [Int] = []
    var height: CGFloat = 0
}

// MARK: - Equipment Index Bar

private struct EquipmentIndexBar: View {
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
                        Image(systemName: equipment.sfSymbol)
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(activeEquipment == equipment ? Color.accentColor : Color.secondary)
                            .accessibilityLabel(equipment.localizedName)
                    }
                }
                .frame(width: Self.barWidth)
                .padding(.vertical, Self.verticalPadding)
                .background(
                    Capsule().fill(Color(.tertiarySystemFill).opacity(0.7))
                )
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
