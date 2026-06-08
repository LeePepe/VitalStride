import SwiftData
import SwiftUI
import VitalModels

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.nameEn) private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var selectedMuscleGroup: MuscleGroup?
    let onSelect: (Exercise) -> Void

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
        [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)]
    }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    ContentUnavailableView(
                        "动作库为空",
                        systemImage: "tray",
                        description: Text("请先导入预置动作库")
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
            .searchable(text: $searchText, prompt: "搜索动作")
            .navigationTitle("选择动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - Muscle Group Sidebar

    private var muscleGroupSidebar: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                sidebarItem(
                    icon: "square.grid.2x2",
                    label: "全部",
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(equipmentGroups, id: \.0) { equipment, items in
                        equipmentSection(equipment: equipment, exercises: items)
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if let group = selectedMuscleGroup {
            ContentUnavailableView(
                "没有动作",
                systemImage: "dumbbell",
                description: Text("\(group.localizedName)分类下暂无动作")
            )
        } else {
            ContentUnavailableView(
                "没有动作",
                systemImage: "dumbbell",
                description: Text("暂无可用动作")
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
                    ExerciseCard(exercise: exercise) {
                        onSelect(exercise)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Exercise Card

private struct ExerciseCard: View {
    let exercise: Exercise
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
