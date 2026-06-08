import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import VitalUI

@main
struct VitalStrideApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let container: ModelContainer?
    private let containerError: String?
    private let healthKitService: HealthKitService
    private let healthDataCache: HealthDataCache

    init() {
        let service = HealthKitService(deviceIdentifier: "ios-display")
        healthKitService = service

        do {
            let modelContainer = try ModelContainerConfiguration.makeContainer()
            container = modelContainer
            containerError = nil

            let persistence = SwiftDataCachePersistence(modelContainer: modelContainer)
            healthDataCache = HealthDataCache(dataProvider: service, persistence: persistence)

            Task {
                ExerciseSeeder.seedIfNeeded(context: modelContainer.mainContext)
                await healthDataCache.hydrate(types: HealthSampleType.overviewTypes)
            }
        } catch {
            container = nil
            containerError = error.localizedDescription
            healthDataCache = HealthDataCache(dataProvider: service)
        }
    }

    var body: some Scene {
        WindowGroup {
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
    }
}
