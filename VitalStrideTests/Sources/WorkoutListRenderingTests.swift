import Foundation
import DesignKit
import HealthKitService
import SwiftData
import Testing
import VitalModels
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif

@testable import VitalStride

// MARK: - WorkoutListView — MY-1359 rendering / windowing / state contract

/// MY-1359 evidence + regression battery.
///
/// The fixture-based reproduction proves the WorkoutList presentation issue
/// (App / HK sections + no source badge + no avg HR) was **not** a data-plane
/// bug. The prior implementation received the same records; it just split
/// them into two sections and stripped the badge / HR fields. These tests
/// pin the new invariants:
///
/// 1. `WorkoutListMerger.merge` produces one interleaved unified array.
/// 2. `WorkoutListView.visibleWindow` keeps every HealthKit item and caps the
///    App items at the paging limit, so "Load more" reveals more App rows
///    while HK rows stay fully visible.
/// 3. `UnifiedWorkout.sourceDeviceKind` surfaces the HK record device kind
///    (so the row can render the correct `WorkoutSourceBadge`).
/// 4. `WorkoutSourceBadge.accessibilityLabel(...)` yields non-empty, distinct
///    labels for the badge variants the row combines into its own a11y label.
@Suite("WorkoutListRendering — MY-1359")
@MainActor
struct WorkoutListRenderingTests {
#if canImport(UIKit)
    @Test("Export Group A four-state Light/Dark snapshot evidence")
    func exportGroupASnapshots() throws {
        let output = URL(fileURLWithPath: "/Users/lee/Development/handoff/vs-rem-1101/snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for width in [375, 393] {
            let height = width == 375 ? 812 : 852
            for appearance in [ColorScheme.light, ColorScheme.dark] {
                for state in [WorkoutListSnapshotMode.populated, .empty, .loading, .error] {
                    let stateName: String
                    switch state {
                    case .populated: stateName = "populated"
                    case .empty: stateName = "empty"
                    case .loading: stateName = "loading"
                    case .error: stateName = "error"
                    case .live: Issue.record("Live mode is not a snapshot state"); continue
                    }

                    let container = try makeSnapshotContainer(populated: state == .populated)
                    let records = state == .populated
                        ? [makeHealthKitRecord(
                            startDate: Date(timeIntervalSince1970: 1_700_000_000),
                            averageHeartRate: 142
                        )]
                        : []
                    let snapshot = WorkoutListView()
                        .modelContainer(container)
                        .environment(AppNavigation())
                        .environment(\.workoutListSnapshotMode, state)
                        .environment(\.workoutListSnapshotRecords, records)
                        .preferredColorScheme(appearance)
                        .designTheme()

                    let host = UIHostingController(rootView: snapshot)
                    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    host.view.frame = window.bounds
                    host.view.layoutIfNeeded()

                    let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
                    let image = renderer.image { _ in
                        host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let data = try #require(image.pngData())
                    #expect(data.count > 15_000)
                    #expect(image.cgImage?.width == width * 3)
                    #expect(image.cgImage?.height == height * 3)
                    #expect(stateName == "populated" || records.isEmpty)
                    let schemeName = appearance == .dark ? "dark" : "light"
                    let filename = "tk1-workout-list-\(stateName)-\(schemeName)-\(width)x\(height).png"
                    try data.write(to: output.appendingPathComponent(filename))
                    window.isHidden = true
                    window.rootViewController = nil
                }
            }
        }
    }

    @Test("Start Workout and Workout Detail production state shells render")
    func renderProductionStateShells() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)
        let workout = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_001_800)
        )
        context.insert(workout)
        try context.save()

        for mode in [WorkoutListSnapshotMode.loading, .error] {
            let startView = AnyView(
                StartWorkoutView(onStart: { _ in })
                    .modelContainer(container)
                    .environment(\.workoutListSnapshotMode, mode)
                    .designTheme()
            )
            let detailView = AnyView(
                WorkoutDetailView(workout: workout)
                    .modelContainer(container)
                    .environment(\.workoutListSnapshotMode, mode)
                    .designTheme()
            )

            for view in [startView, detailView] {
                let host = UIHostingController(rootView: view)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.layoutIfNeeded()
                let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
                let image = renderer.image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let data = try #require(image.pngData())
                #expect(data.count > 15_000)
                #expect(image.cgImage?.width == 1179)
                #expect(image.cgImage?.height == 2556)
                window.isHidden = true
                window.rootViewController = nil
            }
        }
    }
#endif

    private func makeSnapshotContainer(populated: Bool) throws -> ModelContainer {
        let container = try ModelContainerConfiguration.makeTestContainer()
        guard populated else { return container }

        let context = ModelContext(container)
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        let workout = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 1_700_000_000 - 1_800),
            endDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let workoutExercise = WorkoutExercise(order: 0, exercise: exercise)
        workoutExercise.workout = workout
        let exerciseSet = ExerciseSet(order: 0, weight: 60, reps: 8, setType: .working)
        exerciseSet.workoutExercise = workoutExercise
        context.insert(exercise)
        context.insert(workout)
        context.insert(workoutExercise)
        context.insert(exerciseSet)
        try context.save()
        return container
    }

    private func makeHealthKitRecord(
        id: UUID = UUID(),
        activityType: WorkoutActivityType = .running,
        duration: TimeInterval = 1800,
        startDate: Date,
        endDate: Date? = nil,
        sourceName: String? = "Apple Watch",
        sourceDeviceKind: SourceDeviceKind? = .appleWatch,
        averageHeartRate: Int? = nil
    ) -> HealthWorkoutRecord {
        HealthWorkoutRecord(
            id: id,
            activityTypeRawValue: activityType.rawValue,
            duration: duration,
            totalEnergyBurned: 300,
            totalDistance: 5000,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(duration),
            sourceName: sourceName,
            averageHeartRate: averageHeartRate,
            sourceDeviceKind: sourceDeviceKind
        )
    }

    // MARK: Reproduction evidence — presentation, not data-plane

    @Test("Reproduction — the same 3 HK records the buggy UI hid now surface via unified merge")
    func reproductionUnifiedMergeSeesAllHKRecords() throws {
        // fixture: 1 Apple Watch, 1 iPhone, 1 unknown-device HK record
        let watch = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 3_000),
            sourceDeviceKind: .appleWatch,
            averageHeartRate: 145
        )
        let phone = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 2_000),
            sourceDeviceKind: .iPhone
        )
        let unknown = makeHealthKitRecord(
            startDate: Date(timeIntervalSince1970: 1_000),
            sourceDeviceKind: nil
        )

        // Pre-MY-1359 baseline: raw HK count is 3, dedup 0. The buggy view
        // fed them into `partitionBySource().healthKit` → shown in a
        // separate visually-weaker Section. New unified path proves the
        // records were always available.
        let result = WorkoutListMerger.merge(
            appWorkouts: [],
            healthKitRecords: [watch, phone, unknown]
        )
        #expect(result.dedupCount == 0)
        #expect(result.unified.count == 3)
        for item in result.unified {
            if case .healthKit = item {
                // expected — every fixture is a HK record
            } else {
                Issue.record("Expected HK-only unified stream")
            }
        }
    }

    // MARK: Unified section semantics

    @Test("visibleWindow interleaves App/HK by startDate desc — no App-then-HK partition")
    func visibleWindowInterleavesUnified() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let app1 = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 2_500),
            endDate: Date(timeIntervalSince1970: 2_500 + 1_800)
        )
        let app2 = Workout(
            type: .strength,
            startDate: Date(timeIntervalSince1970: 500),
            endDate: Date(timeIntervalSince1970: 500 + 1_800)
        )
        context.insert(app1)
        context.insert(app2)
        try context.save()

        let hkNewer = makeHealthKitRecord(startDate: Date(timeIntervalSince1970: 3_000))
        let hkOlder = makeHealthKitRecord(startDate: Date(timeIntervalSince1970: 1_500))

        let unified = WorkoutListMerger.merge(
            appWorkouts: [app1, app2],
            healthKitRecords: [hkNewer, hkOlder]
        ).unified

        let (visible, totalApp) = WorkoutListView.visibleWindow(unified: unified, appLimit: 100)
        #expect(totalApp == 2)
        #expect(visible.count == 4)
        // Interleave order by startDate desc: hk(3000) → app(2500) → hk(1500) → app(500).
        #expect(visible[0].startDate == Date(timeIntervalSince1970: 3_000))
        #expect(visible[1].startDate == Date(timeIntervalSince1970: 2_500))
        #expect(visible[2].startDate == Date(timeIntervalSince1970: 1_500))
        #expect(visible[3].startDate == Date(timeIntervalSince1970: 500))
    }

    // MARK: Paging semantics (MY-1077 preserved)

    @Test("visibleWindow caps App rows at appLimit but keeps every HealthKit row")
    func visibleWindowCapsAppKeepsHK() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        var appWorkouts: [Workout] = []
        for i in 0..<3 {
            let workout = Workout(
                type: .strength,
                startDate: Date(timeIntervalSince1970: Double(i) * 100),
                endDate: Date(timeIntervalSince1970: Double(i) * 100 + 60)
            )
            context.insert(workout)
            appWorkouts.append(workout)
        }
        try context.save()

        let hkRecords = (0..<4).map { i in
            makeHealthKitRecord(startDate: Date(timeIntervalSince1970: 10_000 + Double(i) * 100))
        }

        let unified = WorkoutListMerger.merge(
            appWorkouts: appWorkouts,
            healthKitRecords: hkRecords
        ).unified
        // appLimit = 1 → 1 App row visible, all 4 HK rows visible.
        let (visible, totalApp) = WorkoutListView.visibleWindow(unified: unified, appLimit: 1)
        #expect(totalApp == 3)
        let appVisible = visible.filter { if case .app = $0 { return true } else { return false } }
        let hkVisible = visible.filter { if case .healthKit = $0 { return true } else { return false } }
        #expect(appVisible.count == 1)
        #expect(hkVisible.count == 4)
    }

    // MARK: Empty state

    @Test("Empty inputs yield empty unified window")
    func emptyEmptyState() {
        let (visible, totalApp) = WorkoutListView.visibleWindow(unified: [], appLimit: 50)
        #expect(visible.isEmpty)
        #expect(totalApp == 0)
    }

    // MARK: Source badge on UnifiedWorkout

    @Test("UnifiedWorkout exposes HealthKit sourceDeviceKind; App returns nil")
    func unifiedWorkoutSourceDeviceKind() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let app = Workout(
            type: .strength,
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )
        context.insert(app)
        try context.save()

        let watch = makeHealthKitRecord(
            startDate: Date(),
            sourceDeviceKind: .appleWatch
        )
        let iphone = makeHealthKitRecord(
            startDate: Date(),
            sourceDeviceKind: .iPhone
        )
        let unknown = makeHealthKitRecord(
            startDate: Date(),
            sourceDeviceKind: nil
        )

        #expect(UnifiedWorkout.app(app).sourceDeviceKind == nil)
        #expect(UnifiedWorkout.healthKit(watch).sourceDeviceKind == .appleWatch)
        #expect(UnifiedWorkout.healthKit(iphone).sourceDeviceKind == .iPhone)
        #expect(UnifiedWorkout.healthKit(unknown).sourceDeviceKind == nil)
    }

    // MARK: Source badge accessibility labels

    @Test("WorkoutSourceBadge a11y labels distinguish App / device kinds / fallback")
    func sourceBadgeA11yLabelsAreDistinct() {
        let app = WorkoutSourceBadge.accessibilityLabel(kind: nil, sourceName: nil, isApp: true)
        let watch = WorkoutSourceBadge.accessibilityLabel(kind: .appleWatch, sourceName: nil, isApp: false)
        let phone = WorkoutSourceBadge.accessibilityLabel(kind: .iPhone, sourceName: nil, isApp: false)
        let pad = WorkoutSourceBadge.accessibilityLabel(kind: .iPad, sourceName: nil, isApp: false)
        let mac = WorkoutSourceBadge.accessibilityLabel(kind: .mac, sourceName: nil, isApp: false)
        let strava = WorkoutSourceBadge.accessibilityLabel(kind: .other, sourceName: "Strava", isApp: false)
        let hk = WorkoutSourceBadge.accessibilityLabel(kind: nil, sourceName: nil, isApp: false)

        #expect(!app.isEmpty)
        #expect(!watch.isEmpty)
        let all = [app, watch, phone, pad, mac, strava, hk]
        // Every label is distinct.
        #expect(Set(all).count == all.count)
        // The named source is embedded in the a11y label.
        #expect(strava.contains("Strava"))
    }
}
