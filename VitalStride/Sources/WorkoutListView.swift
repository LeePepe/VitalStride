// MY-1090 precedent: pre-existing `no_hardcoded_chinese` literals (row
// labels, section headers, a11y strings) predate the `--strict` SwiftLint
// hook and stay silenced at file scope until the shared i18n cleanup. No
// semantic change from this pragma.
// swiftlint:disable no_hardcoded_chinese
import DesignKit
import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import os
#if canImport(UIKit)
import UIKit
#endif

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
    /// Distinct from `healthKitLoadFailed`: raised when
    /// `HealthKitServiceError.authorizationNotDetermined` bubbles out of the
    /// cache fetch. Drives the "Grant HealthKit access" banner + deep-link.
    @State private var healthKitUnauthorized = false
    // Persisted across scene restores so the user's chosen mode survives app
    // backgrounding. `@SceneStorage` for a `RawRepresentable` where `RawValue`
    // is `String` falls back to the default (`.list`) when no stored value
    // exists or when the stored raw value fails to map to a `ViewMode` case,
    // preserving the original T007 default.
    @SceneStorage("workoutViewMode") private var viewMode: ViewMode = .list
    @Environment(\.theme) private var theme

    private var hasAnyWorkouts: Bool {
        !workouts.isEmpty || !healthKitRecords.isEmpty
    }

    @ViewBuilder
    private func listContent(
        unifiedWorkouts: [UnifiedWorkout],
        shouldShowAdviceCard: Bool,
        canLoadMore: Bool,
        bannerState: WorkoutListStateBanner.LoadState?
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

            if let bannerState {
                Section {
                    WorkoutListStateBanner(
                        state: bannerState,
                        onOpenSettings: openSettings
                    )
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if !unifiedWorkouts.isEmpty {
                Section {
                    ForEach(unifiedWorkouts) { item in
                        switch item {
                        case .app(let workout):
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
                        case .healthKit(let record):
                            NavigationLink {
                                HealthKitWorkoutDetailView(record: record)
                            } label: {
                                HealthKitWorkoutRowView(record: record)
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
                        localized: "workout_list.unified_section_header",
                        defaultValue: "Workouts",
                        comment: "Workout list unified section header (all sources combined)"
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
        //
        // MY-1359: List UI now consumes the merged `unified` array directly
        // (single time-line, `startDate` descending). We no longer
        // `partitionBySource` for list rendering — the calendar path keeps
        // using `unifiedWorkouts` as before.
        let mergeResult = WorkoutListMerger.merge(
            appWorkouts: workouts,
            healthKitRecords: healthKitRecords
        )
        let unifiedWorkouts = mergeResult.unified
        let shouldShowAdviceCard = !unifiedWorkouts.isEmpty && privacyConsented
        // Bound only the App rows that hit the expensive `workout.exercises`
        // fault (MY-1077). HealthKit rows carry no faulting cost so they
        // stay fully rendered. We walk the unified stream once and keep every
        // HK record, but cap the App-source stream at `listDisplayLimit`.
        let (visible, totalAppCount) = Self.visibleWindow(
            unified: unifiedWorkouts,
            appLimit: listDisplayLimit
        )
        let canLoadMore = totalAppCount > min(totalAppCount, listDisplayLimit)
        let bannerState = currentBannerState(hasAnyItems: !unifiedWorkouts.isEmpty)
        return NavigationStack {
            Group {
                if !hasAnyWorkouts
                    && !isLoadingHealthKit
                    && !healthKitLoadFailed
                    && !healthKitUnauthorized {
                    ContentUnavailableView(
                        String(localized: "暂无训练记录", comment: "No workouts empty state title"),
                        systemImage: "dumbbell",
                        description: Text(String(localized: "点击 + 开始第一次训练", comment: "No workouts empty state description"))
                    )
                } else {
                    switch viewMode {
                    case .list:
                        listContent(
                            unifiedWorkouts: visible,
                            shouldShowAdviceCard: shouldShowAdviceCard,
                            canLoadMore: canLoadMore,
                            bannerState: bannerState
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

    /// Pure helper: builds the visible slice of the unified list, keeping
    /// every HealthKit item and capping App items at `appLimit`. Returns the
    /// slice + the total App count so the caller can compute the "Load more"
    /// affordance. Exposed for tests.
    static func visibleWindow(
        unified: [UnifiedWorkout],
        appLimit: Int
    ) -> (visible: [UnifiedWorkout], totalAppCount: Int) {
        var visible: [UnifiedWorkout] = []
        visible.reserveCapacity(unified.count)
        var appSeen = 0
        var totalAppCount = 0
        for item in unified {
            switch item {
            case .app:
                totalAppCount += 1
                if appSeen < appLimit {
                    visible.append(item)
                    appSeen += 1
                }
            case .healthKit:
                visible.append(item)
            }
        }
        return (visible, totalAppCount)
    }

    /// Resolves which banner (if any) should be shown above the unified list.
    /// The unified list itself is separately gated by `unifiedWorkouts.isEmpty`
    /// so passing `hasAnyItems` disambiguates loading-over-content from
    /// loading-empty-state.
    private func currentBannerState(
        hasAnyItems: Bool
    ) -> WorkoutListStateBanner.LoadState? {
        if healthKitUnauthorized { return .unauthorized }
        if healthKitLoadFailed { return .failed }
        if isLoadingHealthKit && !hasAnyItems { return .loading }
        return nil
    }

    private func openSettings() {
        WorkoutListStateBanner.openSettings()
    }

    private func loadHealthKitWorkouts() async {
        isLoadingHealthKit = true
        healthKitLoadFailed = false
        healthKitUnauthorized = false
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
            // Split unauthorized from generic failure so the banner UI can
            // route the user to Settings instead of showing an opaque error.
            // Constitution §I: log only the branch label, never the record
            // payload / HR / energy / distance values.
            if case HealthKitServiceError.authorizationNotDetermined = error {
                logger.info("workout_list_hk_fetch state=unauthorized")
                healthKitUnauthorized = true
            } else {
                logger.error("HealthKit workout load failed: \(error.localizedDescription)")
                healthKitLoadFailed = true
            }
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
    @Environment(\.theme) private var theme
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(workout.startDate, style: .date)
                    .font(.headline)
                Spacer()
                Text(workout.startDate, style: .time)
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
            }
            HStack {
                let exerciseCount = workout.exercises?.count ?? 0
                Label(
                    String(localized: "\(exerciseCount) 个动作", comment: "Exercise count label"),
                    systemImage: "figure.strengthtraining.traditional"
                )
                .font(.subheadline)
                .foregroundStyle(theme.neutrals.text2)

                if let endDate = workout.endDate {
                    Spacer()
                    let totalSeconds = Int(endDate.timeIntervalSince(workout.startDate))
                    let minutes = totalSeconds / 60
                    let hours = minutes / 60
                    let remainingMinutes = minutes % 60
                    Text(hours > 0 ? "\(hours)h \(remainingMinutes)m" : "\(minutes)m")
                        .font(.subheadline)
                        .foregroundStyle(theme.neutrals.text2)
                }
            }
            HStack {
                WorkoutSourceBadge(kind: nil, sourceName: nil, isApp: true)
                Spacer()
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        let exerciseCount = workout.exercises?.count ?? 0
        let exercisesFmt = String(
            localized: "workout_list.row.exercise_count_a11y",
            defaultValue: "%lld exercises",
            comment: "VoiceOver: number of exercises in an App workout (MY-1359)"
        )
        var parts: [String] = [
            workout.startDate.formatted(.dateTime.year().month().day()),
            String(format: exercisesFmt, exerciseCount),
            WorkoutSourceBadge.accessibilityLabel(kind: nil, sourceName: nil, isApp: true),
        ]
        if let endDate = workout.endDate {
            let minutes = Int(endDate.timeIntervalSince(workout.startDate)) / 60
            let minutesFmt = String(
                localized: "workout_list.row.duration_minutes_a11y",
                defaultValue: "%lld minutes",
                comment: "VoiceOver: workout duration in minutes (MY-1359)"
            )
            parts.append(String(format: minutesFmt, minutes))
        }
        return parts.joined(separator: "，")
    }
}

#Preview {
    WorkoutListView()
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
        .environment(AppNavigation())
        .designThemePreview()
}

// MARK: - Fixture Previews (MY-1359 P0)
//
// Preview-only, deterministic fixture that renders the same List content
// `WorkoutListView` shows for each of the five documented states, without
// touching HealthKit, SwiftData `@Query`, or `AppNavigation`. This gives
// the design gate reproducible captures in Xcode Previews for the report.

private struct WorkoutListPreviewFixture: View {
    enum Scenario {
        case loading
        case empty
        case failed
        case unauthorized
        case mixed
    }

    let scenario: Scenario

    private var bannerState: WorkoutListStateBanner.LoadState? {
        switch scenario {
        case .loading: .loading
        case .failed: .failed
        case .unauthorized: .unauthorized
        case .empty, .mixed: nil
        }
    }

    private var showsList: Bool {
        switch scenario {
        case .empty: false
        default: true
        }
    }

    private static let referenceDate = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01T00:00:00Z

    private var healthKitRows: [HealthWorkoutRecord] {
        switch scenario {
        case .mixed:
            return [
                HealthWorkoutRecord(
                    id: UUID(),
                    activityTypeRawValue: 37, // running
                    duration: 45 * 60,
                    totalEnergyBurned: 420,
                    totalDistance: 8000,
                    startDate: Self.referenceDate.addingTimeInterval(-2 * 3600),
                    endDate: Self.referenceDate.addingTimeInterval(-2 * 3600 + 45 * 60),
                    sourceName: "Apple Watch",
                    averageHeartRate: 142,
                    sourceDeviceKind: .appleWatch,
                    isUserEntered: false
                ),
                HealthWorkoutRecord(
                    id: UUID(),
                    activityTypeRawValue: 52, // walking
                    duration: 25 * 60,
                    totalEnergyBurned: 90,
                    totalDistance: 2200,
                    startDate: Self.referenceDate.addingTimeInterval(-4 * 3600),
                    endDate: Self.referenceDate.addingTimeInterval(-4 * 3600 + 25 * 60),
                    sourceName: "iPhone",
                    averageHeartRate: 108,
                    sourceDeviceKind: .iPhone,
                    isUserEntered: false
                ),
            ]
        default:
            return []
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let bannerState {
                    Section {
                        WorkoutListStateBanner(state: bannerState, onOpenSettings: {})
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if showsList {
                    Section {
                        if scenario == .mixed {
                            // App row (fixture placeholder — badge only, since
                            // faulting Workout objects into an in-memory
                            // preview container is out of scope for the design
                            // gate captures).
                            FixtureAppRow(
                                title: String(
                                    localized: "workout_list.preview.fixture_app_title",
                                    defaultValue: "VitalStride workout",
                                    comment: "Preview-only App row title (MY-1359 fixtures)"
                                ),
                                subtitle: String(
                                    localized: "workout_list.preview.fixture_app_subtitle",
                                    defaultValue: "6 exercises · 42 min",
                                    comment: "Preview-only App row subtitle (MY-1359 fixtures)"
                                )
                            )
                            ForEach(healthKitRows) { record in
                                HealthKitWorkoutRowView(record: record)
                            }
                        }
                    } header: {
                        Text(String(
                            localized: "workout_list.unified_section_header",
                            defaultValue: "Workouts",
                            comment: "Workout list unified section header (all sources combined)"
                        ))
                        .accessibilityAddTraits(.isHeader)
                    }
                } else if scenario == .empty {
                    Section {
                        ContentUnavailableView(
                            String(
                                localized: "workout_list.preview.empty_title",
                                defaultValue: "No workouts yet",
                                comment: "Preview-only empty state title (MY-1359 fixtures)"
                            ),
                            systemImage: "dumbbell",
                            description: Text(String(
                                localized: "workout_list.preview.empty_subtitle",
                                defaultValue: "Tap + to start your first workout",
                                comment: "Preview-only empty state subtitle (MY-1359 fixtures)"
                            ))
                        )
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(Text(String(
                localized: "workout_list.preview.nav_title",
                defaultValue: "Workouts",
                comment: "Preview-only nav title (MY-1359 fixtures)"
            )))
        }
    }
}

private struct FixtureAppRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Space.gap) {
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(title)
                    .font(TypeScale.body.weight(.semibold))
                    .foregroundStyle(theme.neutrals.text1)
                Text(subtitle)
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text2)
            }
            Spacer()
            WorkoutSourceBadge(kind: nil, sourceName: nil, isApp: true)
        }
        .padding(.vertical, Space.hair)
    }
}

#Preview("Fixture — loading (light)") {
    WorkoutListPreviewFixture(scenario: .loading)
        .designThemePreview()
}

#Preview("Fixture — empty (light)") {
    WorkoutListPreviewFixture(scenario: .empty)
        .designThemePreview()
}

#Preview("Fixture — failed (light)") {
    WorkoutListPreviewFixture(scenario: .failed)
        .designThemePreview()
}

#Preview("Fixture — unauthorized (light)") {
    WorkoutListPreviewFixture(scenario: .unauthorized)
        .designThemePreview()
}

#Preview("Fixture — mixed App+HK (light)") {
    WorkoutListPreviewFixture(scenario: .mixed)
        .designThemePreview()
}

#Preview("Fixture — mixed App+HK (dark, Large)") {
    WorkoutListPreviewFixture(scenario: .mixed)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.large)
        .designThemePreview()
}

#Preview("Fixture — unauthorized (dark, Large)") {
    WorkoutListPreviewFixture(scenario: .unauthorized)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.large)
        .designThemePreview()
}
