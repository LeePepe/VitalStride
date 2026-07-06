import SwiftData
import SwiftUI
import VitalModels

enum WorkoutStartSource {
    case blank
    case fromWorkout(Workout)
    case fromTemplate(WorkoutTemplate)
    case resume(Workout)
}

struct StartWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var recentWorkouts: [Workout]
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]
    let onStart: (WorkoutStartSource) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        dismiss()
                        onStart(.blank)
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("空白训练")
                                    .font(.body)
                                Text("从零开始，逐个添加动作")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                if !recentWorkouts.isEmpty {
                    Section("从历史复制") {
                        ForEach(recentWorkouts.prefix(5)) { workout in
                            Button {
                                dismiss()
                                onStart(.fromWorkout(workout))
                            } label: {
                                HistoryWorkoutRow(workout: workout)
                            }
                        }
                    }
                }

                if !templates.isEmpty {
                    Section("从模板开始") {
                        ForEach(templates) { template in
                            Button {
                                dismiss()
                                onStart(.fromTemplate(template))
                            } label: {
                                TemplateRow(template: template)
                            }
                        }
                    }
                }
            }
            .navigationTitle("开始训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct HistoryWorkoutRow: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.startDate, style: .date)
                .font(.body)
            let exerciseNames = (workout.exercises ?? [])
                .sorted { $0.order < $1.order }
                .compactMap { $0.exercise?.localizedName }
            if !exerciseNames.isEmpty {
                Text(exerciseNames.joined(separator: "、"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TemplateRow: View {
    let template: WorkoutTemplate
    @Environment(\.modelContext) private var modelContext
    @State private var historicalAverage: TimeInterval?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(template.name)
                .font(.body)
            HStack(spacing: 4) {
                Text("\(exerciseCount) 个动作")
                Text(verbatim: "·")
                durationText
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .task(id: template.persistentModelID) {
            historicalAverage = Self.computeHistoricalAverage(
                for: template,
                in: modelContext
            )
        }
    }

    private var exerciseCount: Int {
        template.exercises?.count ?? 0
    }

    private var durationText: Text {
        let seconds = template.estimatedDuration(historicalAverage: historicalAverage)
        guard seconds > 0 else {
            return Text(verbatim: "—")
        }
        let minutes = Int((seconds / 60).rounded())
        return Text(String(localized: "约 \(minutes) 分钟"))
    }

    /// Bounded lookup of recent finished workouts whose exercise set matches
    /// this template's exercise set. Returns the mean duration of up to
    /// `maxMatchedWorkouts` most-recent matches, or `nil` when there is no
    /// signal yet.
    ///
    /// The query stays in the app target on purpose: `VitalModels` remains
    /// query-free (Constitution III), and the pure `estimatedDuration`
    /// function receives the average as a plain parameter.
    private static func computeHistoricalAverage(
        for template: WorkoutTemplate,
        in context: ModelContext
    ) -> TimeInterval? {
        let templateExerciseIDs = Set(
            (template.exercises ?? []).compactMap { $0.exercise?.persistentModelID }
        )
        guard !templateExerciseIDs.isEmpty else { return nil }

        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.endDate != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = recentWorkoutScanLimit
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]

        guard let recent = try? context.fetch(descriptor) else { return nil }

        let matched = recent.lazy
            .filter { workout in
                let ids = Set((workout.exercises ?? []).compactMap { $0.exercise?.persistentModelID })
                return ids == templateExerciseIDs
            }
            .prefix(maxMatchedWorkouts)

        let durations = matched.compactMap { workout -> TimeInterval? in
            guard let endDate = workout.endDate else { return nil }
            let interval = endDate.timeIntervalSince(workout.startDate)
            return interval > 0 ? interval : nil
        }

        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    private static let recentWorkoutScanLimit = 30
    private static let maxMatchedWorkouts = 5
}

#Preview {
    StartWorkoutView { _ in }
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
