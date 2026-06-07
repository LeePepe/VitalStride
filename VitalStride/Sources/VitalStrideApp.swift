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
        healthDataCache = HealthDataCache(dataProvider: service)

        do {
            let modelContainer = try ModelContainerConfiguration.makeContainer()
            container = modelContainer
            containerError = nil
            Task {
                ExerciseSeeder.seedIfNeeded(context: modelContainer.mainContext)
            }
        } catch {
            container = nil
            containerError = error.localizedDescription
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
