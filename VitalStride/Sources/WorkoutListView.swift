import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "WorkoutList")

struct WorkoutListView: View {
    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var workouts: [Workout]
    @Environment(\.modelContext) private var modelContext
    @AppStorage(aiPrivacyConsentKey) private var privacyConsented = false
    @State private var adviceViewModel = TrainingAdviceViewModel()
    @State private var showingStartOptions = false
    @State private var showingActiveWorkout = false
    @State private var pendingSource: WorkoutStartSource?
    @State private var workoutToDelete: Workout?
    @State private var showingDeleteError = false

    private var shouldShowAdviceCard: Bool {
        !workouts.isEmpty && privacyConsented
    }

    var body: some View {
        NavigationStack {
            Group {
                if workouts.isEmpty {
                    ContentUnavailableView(
                        "暂无训练记录",
                        systemImage: "dumbbell",
                        description: Text("点击 + 开始第一次训练")
                    )
                } else {
                    List {
                        if shouldShowAdviceCard {
                            Section {
                                AITrainingAdviceCard(
                                    state: adviceViewModel.state,
                                    isExpanded: adviceViewModel.isExpanded,
                                    onToggleExpand: { adviceViewModel.toggleExpand() },
                                    onRefresh: { adviceViewModel.refresh(modelContext: modelContext) }
                                )
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }

                        Section {
                            ForEach(workouts) { workout in
                                NavigationLink {
                                    WorkoutDetailView(workout: workout)
                                } label: {
                                    WorkoutRowView(workout: workout)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        workoutToDelete = workout
                                    } label: {
                                        Label(
                                            String(localized: "删除", comment: "Delete swipe action"),
                                            systemImage: "trash"
                                        )
                                    }
                                    .accessibilityLabel(String(localized: "删除训练", comment: "Delete workout a11y"))
                                }
                            }
                        }
                    }
                    .task {
                        guard privacyConsented else { return }
                        adviceViewModel.loadAdviceIfNeeded(modelContext: modelContext)
                    }
                }
            }
            .navigationTitle("训练")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("开始训练", systemImage: "plus") {
                        showingStartOptions = true
                    }
                }
            }
            .alert(
                String(localized: "确认删除", comment: "Delete confirmation alert title"),
                isPresented: Binding(
                    get: { workoutToDelete != nil },
                    set: { if !$0 { workoutToDelete = nil } }
                )
            ) {
                Button(String(localized: "取消", comment: "Cancel button"), role: .cancel) {
                    workoutToDelete = nil
                }
                Button(String(localized: "删除", comment: "Delete confirm button"), role: .destructive) {
                    if let workout = workoutToDelete {
                        deleteWorkout(workout)
                    }
                }
            } message: {
                Text(String(localized: "确定删除这次训练？", comment: "Delete confirmation message"))
            }
            .alert(
                String(localized: "删除失败", comment: "Delete failure alert title"),
                isPresented: $showingDeleteError
            ) {
                Button(String(localized: "好", comment: "OK button")) {}
            } message: {
                Text(String(localized: "无法删除训练记录，请稍后重试。", comment: "Delete failure message"))
            }
            .sheet(isPresented: $showingStartOptions, onDismiss: {
                if pendingSource != nil {
                    showingActiveWorkout = true
                }
            }) {
                StartWorkoutView { source in
                    pendingSource = source
                    showingStartOptions = false
                }
            }
            .fullScreenCover(isPresented: $showingActiveWorkout, onDismiss: {
                pendingSource = nil
            }) {
                ActiveWorkoutView(source: pendingSource ?? .blank)
            }
        }
    }

    private func deleteWorkout(_ workout: Workout) {
        logger.info("Deleting workout source=\(workout.source.rawValue, privacy: .private)")
        modelContext.delete(workout)
        do {
            try modelContext.save()
            workoutToDelete = nil
        } catch {
            logger.error("Failed to save after deleting workout: \(error.localizedDescription, privacy: .private)")
            modelContext.rollback()
            workoutToDelete = nil
            showingDeleteError = true
        }
    }
}

private struct WorkoutRowView: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.startDate, style: .date)
                    .font(.headline)
                Spacer()
                Text(workout.startDate, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack {
                let exerciseCount = workout.exercises?.count ?? 0
                Label(
                    "\(exerciseCount) 个动作",
                    systemImage: "figure.strengthtraining.traditional"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let endDate = workout.endDate {
                    Spacer()
                    let totalSeconds = Int(endDate.timeIntervalSince(workout.startDate))
                    let minutes = totalSeconds / 60
                    let hours = minutes / 60
                    let remainingMinutes = minutes % 60
                    Text(hours > 0 ? "\(hours)h \(remainingMinutes)m" : "\(minutes)m")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    WorkoutListView()
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
