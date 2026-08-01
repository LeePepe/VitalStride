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

        do {
            let modelContainer = try ModelContainerConfiguration.makeContainer()
            container = modelContainer
            containerError = nil

            let persistence = SwiftDataCachePersistence(modelContainer: modelContainer)
            healthDataCache = HealthDataCache(
                dataProvider: service,
                workoutProvider: service,
                persistence: persistence,
                typesProber: service
            )

            let cache = healthDataCache
            let context = modelContainer.mainContext

            Task {
                ExerciseSeeder.seedIfNeeded(context: context)
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
                if testMode != nil {
                    showsPicker = true
                }
            }
            .sheet(isPresented: $showsPicker) {
                if let container {
                    ExercisePickerTestHost(mode: testMode ?? .single)
                        .modelContainer(container)
                }
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
        ZStack(alignment: .topLeading) {
            picker
            if seedTriggerEnabled {
                // round-4 R2: needs a hittable button (not
                // `.accessibilityAction`) because XCUITest calls
                // `app.buttons["ExercisePickerTestSeedTrigger"].tap()`.
                // Visually hidden but retains accessibility hit shape.
                Button(action: seedNow) {
                    Color.clear
                }
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .accessibilityIdentifier("ExercisePickerTestSeedTrigger")
                .accessibilityLabel("Seed test exercise")
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
#endif
