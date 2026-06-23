import HealthKitService
import SwiftData
import SwiftUI
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

    init() {
        let service = HealthKitService(deviceIdentifier: "mac-display")
        healthKitService = service

        #if DEBUG
        Task {
            await TelemetryService.shared.register(ConsoleTelemetryProvider())
        }
        #endif

        do {
            let modelContainer = try ModelContainerConfiguration.makeContainer()
            container = modelContainer
            containerError = nil

            let persistence = SwiftDataCachePersistence(modelContainer: modelContainer)
            healthDataCache = HealthDataCache(
                dataProvider: service,
                persistence: persistence,
                typesProber: service
            )

            Task {
                ExerciseSeeder.seedIfNeeded(context: modelContainer.mainContext)
                let status = try? await service.authorizationStatus()
                if status == .unnecessary {
                    await healthDataCache.hydrate(types: HealthSampleType.overviewTypes)
                } else {
                    await healthDataCache.handleAuthorizationRevoked()
                    service.clearAllAnchors()
                }
            }
        } catch {
            container = nil
            containerError = error.localizedDescription
            healthDataCache = HealthDataCache(dataProvider: service, typesProber: service)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                if hasCompletedOnboarding {
                    MacContentView()
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
    }
}
