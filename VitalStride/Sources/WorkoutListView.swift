import SwiftData
import SwiftUI

extension Exercise {
    var localizedName: String {
        let isZh = Locale.current.language.languageCode?.identifier == "zh"
        return isZh ? (nameZh.isEmpty ? nameEn : nameZh) : (nameEn.isEmpty ? nameZh : nameEn)
    }
}

struct WorkoutListView: View {
    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var workouts: [Workout]
    @State private var showingStartOptions = false
    @State private var showingActiveWorkout = false
    @State private var pendingSource: WorkoutStartSource?

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
                    List(workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutRowView(workout: workout)
                        }
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
