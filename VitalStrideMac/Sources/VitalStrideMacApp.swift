import DesignKit
import HealthKitService
import SwiftData
import SwiftUI
import TelemetryDeckAdapter
import TelemetryKit
import VitalModels
import VitalUI

@main
struct VitalStrideMacApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let container: ModelContainer?
    private let containerError: String?
    private let healthKitService: HealthKitService
    private let healthDataCache: HealthDataCache
    // Spec 019 Stage 3c (T017/T018): shared sink for `RoutingSignal`. Same
    // wiring as `VitalStrideApp` on iOS.
    private let routingSignalStore: RoutingSignalStore?

    init() {
        let service = HealthKitService(deviceIdentifier: "mac-display")
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

        do {
            let modelContainer = try ModelContainerConfiguration.makeContainer()
            container = modelContainer
            containerError = nil

            let persistence = SwiftDataCachePersistence(modelContainer: modelContainer)
            let store = RoutingSignalStore(container: modelContainer)
            routingSignalStore = store
            healthDataCache = HealthDataCache(
                dataProvider: service,
                persistence: persistence,
                typesProber: service,
                revocationHandlers: [store]
            )

            // Copy the stored property into a local before the escaping Task so
            // the closure captures the value, not `self` mid-init (matches the
            // iOS VitalStrideApp init).
            let cache = healthDataCache
            Task {
                ExerciseSeeder.seedIfNeeded(context: modelContainer.mainContext)
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
            healthDataCache = HealthDataCache(dataProvider: service, typesProber: service)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    if hasCompletedOnboarding {
                        MacContentView()
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
        }
    }
}
