import DesignKit
import HealthKitService
import SwiftData
import SwiftUI
import TelemetryDeckAdapter
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
        if let appID = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String,
           !appID.isEmpty {
            let provider = TelemetryDeckAdapter.makeProvider(appID: appID)
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
        }
    }
}
