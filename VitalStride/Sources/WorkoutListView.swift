import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "WorkoutList")
private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "WorkoutList")

/// Number of VitalStride workouts rendered in the list section on first
/// appearance (MY-1077). The full completed history is still fetched — it is
/// needed for HealthKit dedup and for the calendar view — but the list mode
/// `ForEach` renders only this many rows, so the expensive
/// `workout.exercises` fault (per `WorkoutRowView` / row) is bounded to the
/// visible window. Users grow the window via "Load more".
private let initialWorkoutDisplayLimit = 50

/// How many additional rows to reveal in the list section each time the user
/// taps "Load more" (MY-1077).
private let workoutDisplayIncrement = 50

struct WorkoutListView: View {
    /// Unbounded, sort-stable fetch of every completed VitalStride workout.
    /// We intentionally keep this unbounded: HealthKit dedup (see
    /// `WorkoutListMerger.merge`) needs to see every locally-recorded
    /// `healthKitUUID` so mirrored HealthKit records never re-appear in the
    /// Apple Health section, and the calendar view needs the full history to
    /// render every month. The heavy per-row cost (`workout.exercises`
    /// faulting) is bounded separately by paging the list section's
    /// `ForEach` — see `visibleAppUnifiedWorkouts` below.
    @Query(
        filter: #Predicate<Workout> { $0.endDate != nil },
        sort: \Workout.startDate,
        order: .reverse
    ) private var workouts: [Workout]
    @State private var listDisplayLimit = initialWorkoutDisplayLimit
    @Environment(\.modelContext) private var modelContext
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.healthDataCache) private var healthDataCache
    @Environment(AppNavigation.self) private var navigation
    @AppStorage(aiPrivacyConsentKey) private var privacyConsented = false
    @State private var adviceViewModel = TrainingAdviceViewModel()
    @State private var showingStartOptions = false
    @State private var showingActiveWorkout = false
    @State private var pendingSource: WorkoutStartSource?
    @State private var workoutToDelete: Workout?
    @State private var showingDeleteError = false
    @State private var deletionController = WorkoutDeletionController()
    @State private var healthKitRecords: [HealthWorkoutRecord] = []
    @State private var isLoadingHealthKit = false
    @State private var healthKitLoadFailed = false
    // Persisted across scene restores so the user's chosen mode survives app
    // backgrounding. `@SceneStorage` for a `RawRepresentable` where `RawValue`
    // is `String` falls back to the default (`.list`) when no stored value
    // exists or when the stored raw value fails to map to a `ViewMode` case,
    // preserving the original T007 default.
    @SceneStorage("workoutViewMode") private var viewMode: ViewMode = .list

    private var hasAnyWorkouts: Bool {
        !workouts.isEmpty || !healthKitRecords.isEmpty
    }

    @ViewBuilder
    private func listContent(
        visibleAppUnifiedWorkouts: [UnifiedWorkout],
        healthKitUnifiedWorkouts: [UnifiedWorkout],
        shouldShowAdviceCard: Bool,
        canLoadMore: Bool
    ) -> some View {
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

            if isLoadingHealthKit && healthKitUnifiedWorkouts.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .accessibilityLabel(
                                // swiftlint:disable:next no_hardcoded_chinese
                                String(localized: "正在加载更多训练数据", comment: "Loading HK workouts a11y")
                            )
                        Spacer()
                    }
                }
            }

            if healthKitLoadFailed && healthKitUnifiedWorkouts.isEmpty {
                Section {
                    VStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(
                            // swiftlint:disable:next no_hardcoded_chinese
                            String(localized: "无法加载外部训练数据", comment: "HealthKit workout load error")
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if !visibleAppUnifiedWorkouts.isEmpty {
                Section {
                    ForEach(visibleAppUnifiedWorkouts) { item in
                        if case .app(let workout) = item {
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
                                        // swiftlint:disable:next no_hardcoded_chinese
                                        String(localized: "删除", comment: "Delete swipe action"),
                                        systemImage: "trash"
                                    )
                                }
                                .accessibilityLabel(
                                    // swiftlint:disable:next no_hardcoded_chinese
                                    String(localized: "删除训练", comment: "Delete workout a11y")
                                )
                            }
                        }
                    }
                    if canLoadMore {
                        Button {
                            listDisplayLimit += workoutDisplayIncrement
                        } label: {
                            HStack {
                                Spacer()
                                Text(String(
                                    localized: "workout_list_load_more",
                                    comment: "Load more workouts button label"
                                ))
                                .font(.subheadline)
                                Spacer()
                            }
                        }
                        .accessibilityLabel(String(
                            localized: "workout_list_load_more_a11y",
                            comment: "Load more workouts a11y label"
                        ))
                    }
                } header: {
                    Text(String(
                        localized:
                        // swiftlint:disable:next no_hardcoded_chinese
                        "VitalStride 训练",
                        comment: "Workout list section header for workouts recorded in this app"
                    ))
                    .accessibilityAddTraits(.isHeader)
                }
            }

            if !healthKitUnifiedWorkouts.isEmpty {
                Section {
                    ForEach(healthKitUnifiedWorkouts) { item in
                        if case .healthKit(let record) = item {
                            NavigationLink {
                                HealthKitWorkoutDetailView(record: record)
                            } label: {
                                HealthKitWorkoutRowView(record: record)
                            }
                        }
                    }
                } header: {
                    Text(String(
                        localized:
                        // swiftlint:disable:next no_hardcoded_chinese
                        "Apple 健康训练",
                        comment: "Workout list section header for workouts from Apple HealthKit"
                    ))
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .task {
            guard privacyConsented else { return }
            adviceViewModel.loadAdviceIfNeeded(modelContext: modelContext)
        }
    }

    var body: some View {
        // Merge the *full* completed-workout set with the HealthKit records —
        // dedup (MY-1077 P0 regression fix) and calendar rendering both need
        // to see every VitalStride `healthKitUUID`, not just the loaded page.
        let unifiedWorkouts = WorkoutListMerger.merge(
            appWorkouts: workouts,
            healthKitRecords: healthKitRecords
        ).unified
        let partitioned = WorkoutListMerger.partitionBySource(unifiedWorkouts)
        let shouldShowAdviceCard = !unifiedWorkouts.isEmpty && privacyConsented
        // Bound only the rows the list mode actually renders — that's where
        // the per-row `workout.exercises` fault is expensive (MY-1077). The
        // calendar view continues to see the full history via `unifiedWorkouts`.
        let visibleApp = Array(partitioned.app.prefix(listDisplayLimit))
        let canLoadMore = partitioned.app.count > visibleApp.count
        return NavigationStack {
            Group {
                if !hasAnyWorkouts && !isLoadingHealthKit && !healthKitLoadFailed {
                    ContentUnavailableView(
                        String(localized: "暂无训练记录", comment: "No workouts empty state title"),
                        systemImage: "dumbbell",
                        description: Text(String(localized: "点击 + 开始第一次训练", comment: "No workouts empty state description"))
                    )
                } else {
                    switch viewMode {
                    case .list:
                        listContent(
                            visibleAppUnifiedWorkouts: visibleApp,
                            healthKitUnifiedWorkouts: partitioned.healthKit,
                            shouldShowAdviceCard: shouldShowAdviceCard,
                            canLoadMore: canLoadMore
                        )
                    case .calendar:
                        // T009: render the current-month LazyVGrid calendar.
                        // Month navigation (T010), day-tap detail navigation
                        // (T011), previews (T013), and the a11y audit pass
                        // (T014) land in later tasks per
                        // specs/011-workout-calendar/tasks.md.
                        WorkoutCalendarView(workouts: unifiedWorkouts)
                    }
                }
            }
            .task {
                await loadHealthKitWorkouts()
            }
            .navigationTitle(
                // swiftlint:disable:next no_hardcoded_chinese
                String(localized: "训练", comment: "Workout tab title")
            )
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(
                        // swiftlint:disable:next no_hardcoded_chinese
                        String(localized: "训练视图模式", comment: "Workout view mode picker label"),
                        selection: $viewMode
                    ) {
                        // swiftlint:disable:next no_hardcoded_chinese
                        Text(String(localized: "列表", comment: "Workout list mode label"))
                            .tag(ViewMode.list)
                        // swiftlint:disable:next no_hardcoded_chinese
                        Text(String(localized: "日历", comment: "Workout calendar mode label"))
                            .tag(ViewMode.calendar)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(
                        // swiftlint:disable:next no_hardcoded_chinese
                        String(localized: "训练视图模式", comment: "Workout view mode picker a11y label")
                    )
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        String(localized: "开始训练", comment: "Start workout toolbar button"),
                        systemImage: "plus"
                    ) {
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
            .onAppear { triggerResumeIfNeeded() }
            .onChange(of: navigation.crashRecoveryResume?.persistentModelID) { _, _ in
                triggerResumeIfNeeded()
            }
        }
    }

    private func triggerResumeIfNeeded() {
        guard let workout = navigation.crashRecoveryResume else { return }
        guard !showingActiveWorkout else { return }
        pendingSource = .resume(workout)
        showingActiveWorkout = true
        navigation.crashRecoveryResume = nil
    }

    private func loadHealthKitWorkouts() async {
        isLoadingHealthKit = true
        healthKitLoadFailed = false
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("workout_list_hk_fetch", id: signpostID)
        let start = ContinuousClock.now

        defer {
            signposter.endInterval("workout_list_hk_fetch", state)
            isLoadingHealthKit = false
        }

        do {
            let records = try await healthDataCache.workoutData()
            guard !Task.isCancelled else { return }

            let elapsed = start.duration(to: ContinuousClock.now)
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info(
                "workout_list_hk_fetch_duration_ms=\(ms) count=\(records.count) success=true"
            )

            healthKitRecords = records

            let result = WorkoutListMerger.merge(
                appWorkouts: workouts,
                healthKitRecords: records
            )
            logger.info(
                "workout_list_dedup_count=\(result.dedupCount)"
            )
            logger.info(
                "workout_list_unified_count local=\(workouts.count) hk=\(records.count) total=\(result.unified.count)"
            )
        } catch {
            guard !Task.isCancelled else { return }
            logger.error("HealthKit workout load failed: \(error.localizedDescription)")
            healthKitLoadFailed = true
        }
    }

    private func deleteWorkout(_ workout: Workout) {
        let hkService = healthKitService
        WorkoutListView.performSwipeDelete(
            workout: workout,
            workoutToDelete: Binding(
                get: { workoutToDelete },
                set: { workoutToDelete = $0 }
            ),
            showingDeleteError: Binding(
                get: { showingDeleteError },
                set: { showingDeleteError = $0 }
            ),
            in: modelContext,
            healthKitDelete: { uuid in
                try await hkService.deleteWorkout(healthKitUUID: uuid)
            },
            controller: deletionController
        )
    }

    /// The production swipe-to-delete flow, extracted so tests exercise the
    /// exact same sequence the view uses (see MY-1094 P1 v2 repair).
    ///
    /// Behavior contract:
    /// - `workoutToDelete` is cleared **synchronously** so the confirmation
    ///   alert's binding drops the reference before any async work starts.
    /// - Delegates to `WorkoutDeletionController.beginDelete`. On success the
    ///   controller stays gated; the list view stays mounted so we `reset()`
    ///   it once the deleted row is gone. On error we set `showingDeleteError`.
    ///
    /// `healthKitDelete` is passed as a `@Sendable` closure so tests can
    /// exercise this helper without constructing a live `HealthKitService`
    /// (the view binds it to `hkService.deleteWorkout(healthKitUUID:)`).
    ///
    /// Returns the delete `Task` for tests to await; production callers ignore.
    @discardableResult
    static func performSwipeDelete(
        workout: Workout,
        workoutToDelete: Binding<Workout?>,
        showingDeleteError: Binding<Bool>,
        in modelContext: ModelContext,
        healthKitDelete: @Sendable @escaping (String) async throws -> Void,
        controller: WorkoutDeletionController
    ) -> Task<Void, Never> {
        // Clear the deletion target immediately so the confirmation alert's
        // binding stops holding a reference to the about-to-be-deleted model.
        workoutToDelete.wrappedValue = nil

        return controller.beginDelete(
            workout: workout,
            in: modelContext,
            healthKitDelete: healthKitDelete,
            onFinished: {
                // List view stays mounted across deletes, so release the
                // controller's terminal-success gate for the next swipe.
                controller.reset()
            },
            onError: { _ in showingDeleteError.wrappedValue = true }
        )
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
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
        .environment(AppNavigation())
}
