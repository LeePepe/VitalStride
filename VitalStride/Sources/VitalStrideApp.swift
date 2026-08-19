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
        let isExercisePickerUITest = ProcessInfo.processInfo.arguments.contains(
            "-ExercisePickerTestMode"
        )
        #else
        let isExercisePickerUITest = false
        #endif

        do {
            // The focus harness must not depend on the production persistent
            // CloudKit store being available on a freshly booted CI
            // simulator. Use the same in-memory container for app startup,
            // the harness seed, and ExercisePickerView's @Query.
            let modelContainer = if isExercisePickerUITest {
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
                if !isExercisePickerUITest {
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
#endif
