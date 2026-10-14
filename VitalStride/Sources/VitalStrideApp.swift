import DesignKit
import HealthKitService
import SwiftData
import SwiftUI
import AptabaseAdapter
import TelemetryKit
import VitalModels
import VitalUI

@main
struct VitalStrideApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let container: ModelContainer?
    private let containerError: String?
    private let healthKitService: HealthKitService
    private let healthDataCache: HealthDataCache
    // Spec 019 Stage 3c (T017/T018): shared sink for `RoutingSignal` emitted
    // by every `AIRouter.execute`. `nil` when the SwiftData container failed
    // to build — the environment key resolves to `nil` and every AI call
    // site falls back to the router's `NoOpRoutingSignalSink`.
    private let routingSignalStore: RoutingSignalStore?
    #if canImport(MetricKit) && !os(watchOS)
    // Retained for the app's lifetime so it keeps receiving MetricKit
    // diagnostic payloads (crash + hang) delivered on subsequent launches.
    private let diagnosticCollector = MetricKitDiagnosticCollector()
    #endif

    init() {
        // spec 015-glitchtip-crash-reporting (MY-1311/T002): wire sentry-cocoa
        // as early as possible so any subsequent init crash is captured. DEBUG
        // + missing-DSN paths are fail-safe no-ops (see `CrashReporting`).
        CrashReporting.start()

        let service = HealthKitService(deviceIdentifier: "ios-display")
        healthKitService = service

        #if DEBUG
        Task {
            await TelemetryService.shared.register(ConsoleTelemetryProvider())
        }
        #else
        if let appKey = Bundle.main.object(forInfoDictionaryKey: "AptabaseAppKey") as? String,
           !appKey.isEmpty,
           let host = Bundle.main.object(forInfoDictionaryKey: "AptabaseHost") as? String,
           !host.isEmpty {
            let provider = AptabaseAdapter.makeProvider(appKey: appKey, host: host)
            Task { await TelemetryService.shared.register(provider) }
        }
        #endif

        #if canImport(MetricKit) && !os(watchOS)
        // ADR-0012: begin collecting MetricKit crash/hang diagnostics. In DEBUG
        // the collector logs locally and does not transport (§Decision.4).
        diagnosticCollector.start()
        #endif

        #if DEBUG
        let isUITest = ProcessInfo.processInfo.arguments.contains("-ExercisePickerTestMode")
            || ProcessInfo.processInfo.arguments.contains("-SnackbarA11yTestMode")
            || ProcessInfo.processInfo.arguments.contains("-SubSetRouteTestMode")
        let isExercisePickerUITest = ProcessInfo.processInfo.arguments.contains(
            "-ExercisePickerTestMode"
        )
        let isSubSetRouteUITest = ProcessInfo.processInfo.arguments.contains(
            "-SubSetRouteTestMode"
        )
        #else
        let isUITest = false
        let isExercisePickerUITest = false
        let isSubSetRouteUITest = false
        #endif

        do {
            // The focus harness must not depend on the production persistent
            // CloudKit store being available on a freshly booted CI
            // simulator. Use the same in-memory container for app startup,
            // the harness seed, and ExercisePickerView's @Query.
            let modelContainer = if isUITest {
                try ModelContainerConfiguration.makeTestContainer()
            } else {
                try ModelContainerConfiguration.makeContainer()
            }
            container = modelContainer
            containerError = nil

            let persistence = SwiftDataCachePersistence(modelContainer: modelContainer)
            let store = RoutingSignalStore(container: modelContainer)
            routingSignalStore = store
            healthDataCache = HealthDataCache(
                dataProvider: service,
                workoutProvider: service,
                persistence: persistence,
                typesProber: service,
                revocationHandlers: [store]
            )

            let cache = healthDataCache
            let context = modelContainer.mainContext

            Task {
                if !isUITest {
                    ExerciseSeeder.seedIfNeeded(context: context)
                }
                let status = try? await service.authorizationStatus()
                if status == .unnecessary {
                    await cache.hydrate(types: HealthSampleType.overviewTypes)
                } else {
                    await cache.handleAuthorizationRevoked()
                    service.clearAllAnchors()
                }
            }
        } catch {
            container = nil
            containerError = error.localizedDescription
            routingSignalStore = nil
            healthDataCache = HealthDataCache(dataProvider: service, workoutProvider: service, typesProber: service)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    if hasCompletedOnboarding {
                        ContentView()
                            .modelContainer(container)
                            .environment(\.healthDataCache, healthDataCache)
                            .environment(\.healthKitService, healthKitService)
                            .environment(\.routingSignalStore, routingSignalStore)
                    } else {
                        OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    }
                } else {
                    DataStoreErrorView(errorMessage: containerError ?? "Unknown error")
                }
            }
            .designTheme(seed: .teal, neutral: .slate)
            #if DEBUG
            // spec 020 (MY-1370): XCUITest entry point for ExercisePicker
            // search focus regression. Guarded by `-ExercisePickerTestMode`
            // launch argument so it never affects normal debug or release
            // runs. Presents ExercisePickerView as a modal sheet, and (with
            // `-ExercisePickerTestSeedTrigger 1`) mounts a hittable seed
            // button that inserts a deterministic Exercise into SwiftData
            // to drive the @Query refresh test (T4).
            .modifier(ExercisePickerTestHarnessModifier(container: container))
            // MY-1446 P1-5: XCUITest entry point for snackbar accessibility
            // regression. Presents slotEnvelope with known labels so XCUI
            // can verify the accessibility tree membership contract.
            .modifier(SnackbarA11yTestHarnessModifier())
            // spec 026: XCUITest entry point for SubSet route, full swipe,
            // refusal, geometry, and catalog identity acceptance.
            .modifier(SubSetRouteTestHarnessModifier(container: container))
            #endif
        }
    }
}

#if DEBUG
private struct ExercisePickerTestHarnessModifier: ViewModifier {
    let container: ModelContainer?
    @State private var testMode: ExercisePickerTestMode? = ExercisePickerTestMode.fromLaunchArguments()
    @State private var showsPicker: Bool = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard testMode != nil, let container else { return }
                seedMinimalCatalogIfNeeded(in: container)
                showsPicker = true
            }
            .sheet(isPresented: $showsPicker) {
                if let container {
                    ExercisePickerTestHost(mode: testMode ?? .single)
                        .modelContainer(container)
                }
            }
    }

    /// The focus suite needs one known populated result ("bench") plus the
    /// ability to cross into the empty state. It does not need the production
    /// catalog migration, which is covered by `ExerciseSeederTests`.
    private func seedMinimalCatalogIfNeeded(in isolatedContainer: ModelContainer) {
        let context = isolatedContainer.mainContext
        let descriptor = FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.nameEn == "Bench Press" }
        )
        guard let matches = try? context.fetch(descriptor), matches.isEmpty else { return }

        context.insert(
            Exercise(
                nameEn: "Bench Press",
                nameZh: "Bench Press",
                muscleGroup: .chest,
                equipment: .barbell
            )
        )
        do {
            try context.save()
        } catch {
            print("[ExercisePickerTestHarness] baseline seed failed: \(error)")
        }
    }
}

private enum ExercisePickerTestMode: String {
    case single
    case multiple

    static func fromLaunchArguments() -> ExercisePickerTestMode? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ExercisePickerTestMode"),
              idx + 1 < args.count else { return nil }
        switch args[idx + 1] {
        case "single": return .single
        case "multi", "multiple": return .multiple
        default: return nil
        }
    }
}

private struct ExercisePickerTestHost: View {
    let mode: ExercisePickerTestMode
    @Environment(\.modelContext) private var modelContext
    @State private var didSeed = false

    private var seedTriggerEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-ExercisePickerTestSeedTrigger"),
              idx + 1 < args.count else { return false }
        return args[idx + 1] == "1"
    }

    var body: some View {
        ZStack(alignment: .top) {
            picker
            if seedTriggerEnabled {
                // round-4 R2: needs a hittable button (not
                // `.accessibilityAction`) because XCUITest calls
                // `app.buttons["ExercisePickerTestSeedTrigger"].tap()`.
                // 44x44 hit target (Constitution §H), placed at the very
                // top-left with 0.02 opacity — visible enough for the
                // accessibility engine to consider hittable, invisible to
                // the naked eye, and doesn't overlap the picker's
                // navigation-bar cancel button which sits below the
                // safe-area top inset.
                Button(action: seedNow) {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(0.02)
                .accessibilityIdentifier("ExercisePickerTestSeedTrigger")
                .accessibilityLabel("Seed test exercise")
                .zIndex(9999)
            }
        }
    }

    @ViewBuilder
    private var picker: some View {
        switch mode {
        case .single:
            ExercisePickerView(onSelect: { _ in })
        case .multiple:
            ExercisePickerView(onConfirm: { _ in })
        }
    }

    private func seedNow() {
        guard !didSeed else { return }
        didSeed = true
        // round-5/6 R1/R2: deterministic name + real Exercise init labels,
        // real enum cases (`MuscleGroup.legs`, `Equipment.barbell`). nameZh
        // == nameEn so `localizedName` returns the same string regardless
        // of simulator locale — XCUITest asserts
        // `staticTexts["TestSeedExercise"]`.
        let seed = Exercise(
            nameEn: "TestSeedExercise",
            nameZh: "TestSeedExercise",
            muscleGroup: .legs,
            equipment: .barbell
        )
        modelContext.insert(seed)
        do {
            try modelContext.save()
        } catch {
            // #if DEBUG test harness only — surface via signpost, never
            // silently swallow. XCUITest asserts on the resulting row
            // appearing in the grid, so a save failure will fail the test
            // loudly regardless.
            print("[ExercisePickerTestHarness] seed save failed: \(error)")
        }
    }
}

// MARK: - MY-1446 P1-5: Snackbar Accessibility XCUITest harness

/// Presents `slotEnvelope` full-screen when `-SnackbarA11yTestMode undo|rest`
/// launch argument is detected. XCUI tests verify that only the active slot's
/// content appears in the accessibility tree — the gold-standard semantic
/// assertion for `.accessibilityHidden` behavior.
private struct SnackbarA11yTestHarnessModifier: ViewModifier {
    @State private var testSlot: BottomSnackbarSlot? = Self.slotFromLaunchArguments()

    func body(content: Content) -> some View {
        if let slot = testSlot {
            SnackbarA11yTestHost(slot: slot)
        } else {
            content
        }
    }

    private static func slotFromLaunchArguments() -> BottomSnackbarSlot? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-SnackbarA11yTestMode"),
              idx + 1 < args.count else { return nil }
        switch args[idx + 1] {
        case "undo": return .undo
        case "rest": return .rest
        default: return nil
        }
    }
}

/// Minimal full-screen host rendering `slotEnvelope` with deterministic
/// accessibility labels for XCUI tree inspection.
private struct SnackbarA11yTestHost: View {
    let slot: BottomSnackbarSlot

    var body: some View {
        ActiveWorkoutSnackbarLayout.slotEnvelope(
            snackbarSlot: slot,
            undoContent: {
                Text("Undo content")
                    .accessibilityLabel("snackbar_undo_content")
            },
            restContent: {
                Text("Rest content")
                    .accessibilityLabel("snackbar_rest_content")
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sub-Set Route and Production Deletion XCUITest harness (spec 026)

private struct SubSetRouteTestHarnessModifier: ViewModifier {
    let container: ModelContainer?
    @State private var testMode: SubSetRouteTestMode? = SubSetRouteTestMode.fromLaunchArguments()

    func body(content: Content) -> some View {
        if let testMode, let container {
            SubSetRouteTestHost(mode: testMode)
                .modelContainer(container)
        } else {
            content
        }
    }
}

private enum SubSetRouteTestMode: String {
    case standardPyramidDrop = "standard_pyramid_drop"
    case singleMainWithChild = "single_main_with_child"

    static func fromLaunchArguments() -> SubSetRouteTestMode? {
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "-SubSetRouteTestMode") else { return nil }
        if idx + 1 < args.count {
            switch args[idx + 1] {
            case "single_main_with_child": return .singleMainWithChild
            default: return .standardPyramidDrop
            }
        }
        return .standardPyramidDrop
    }
}

private struct SubSetRouteTestHost: View {
    let mode: SubSetRouteTestMode
    @Environment(\.modelContext) private var modelContext
    @State private var workoutExercise: WorkoutExercise?
    @State private var undoController = SetDeletionUndoController()
    @State private var probe = SetDeletionRequestProbe()
    @State private var setDeletedCount = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let workoutExercise {
                    List {
                        ActiveExerciseSection(
                            workoutExercise: workoutExercise,
                            onSetCompleted: {},
                            onSetDeleted: {
                                setDeletedCount += 1
                            },
                            onReplace: {},
                            onSubstitute: {},
                            onDelete: {},
                            undoController: undoController,
                            requestHandler: probe
                        )
                    }
                    .listStyle(.plain)
                }

                // Probe readout card
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Requests: \(probe.requestCount)")
                            .accessibilityIdentifier("subset_probe_request_count")
                        Text("Seam: \(probe.seamTraversalCount)")
                            .accessibilityIdentifier("subset_probe_seam_count")
                        Text("Callbacks: \(probe.callbackCount)")
                            .accessibilityIdentifier("subset_probe_callback_count")
                    }
                    .font(.caption2)

                    HStack {
                        Text("LastType: \(probe.lastRequestedSetType?.displayName ?? "none")")
                            .accessibilityIdentifier("subset_probe_last_set_type")
                        Text("Undo: \(undoController.hasPendingUndo ? "available" : "none")")
                            .accessibilityIdentifier("subset_probe_undo_state")
                    }
                    .font(.caption2)

                    HStack {
                        if undoController.hasPendingUndo {
                            Button("Undo Action") {
                                _ = undoController.undo(using: modelContext)
                            }
                            .accessibilityIdentifier("subset_probe_undo_button")
                        }
                        Button("Reset Probe") {
                            probe.reset()
                        }
                        .accessibilityIdentifier("subset_probe_reset_button")
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
            }
            .navigationTitle("SubSet Acceptance Host")
            .onAppear {
                seedFixture()
            }
        }
    }

    private func seedFixture() {
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "平板卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        modelContext.insert(exercise)

        let workout = Workout(type: .strength, startDate: Date())
        modelContext.insert(workout)

        let we = WorkoutExercise(order: 0, exercise: exercise)
        we.workout = workout
        modelContext.insert(we)

        switch mode {
        case .standardPyramidDrop:
            let s1 = ExerciseSet(order: 0, weight: 80, reps: 8, setType: .working)
            s1.workoutExercise = we
            modelContext.insert(s1)

            let s2 = ExerciseSet(order: 1, weight: 92, reps: 8, setType: .pyramid)
            s2.workoutExercise = we
            modelContext.insert(s2)

            let s3 = ExerciseSet(order: 2, weight: 68, reps: 8, setType: .dropSet)
            s3.workoutExercise = we
            modelContext.insert(s3)

        case .singleMainWithChild:
            let s1 = ExerciseSet(order: 0, weight: 80, reps: 8, setType: .working)
            s1.workoutExercise = we
            modelContext.insert(s1)

            let s2 = ExerciseSet(order: 1, weight: 68, reps: 8, setType: .dropSet)
            s2.workoutExercise = we
            modelContext.insert(s2)
        }

        do {
            try modelContext.save()
        } catch {
            print("[SubSetRouteTestHost] seed save failed: \(error)")
        }
        self.workoutExercise = we
    }
}
#endif
