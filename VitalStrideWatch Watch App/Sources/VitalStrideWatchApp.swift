import DesignKit
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels
import VitalUI

@main
struct VitalStrideWatchApp: App {
    private let container: ModelContainer?
    private let containerError: String?

    init() {
        #if DEBUG
        Task {
            await TelemetryService.shared.register(ConsoleTelemetryProvider())
        }
        #endif

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
            Group {
                if let container {
                    WatchContentView()
                        .modelContainer(container)
                } else {
                    DataStoreErrorView(errorMessage: containerError ?? "Unknown error")
                }
            }
            .designTheme(seed: .teal, neutral: .slate)
        }
    }
}
