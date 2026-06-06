import SwiftData
import SwiftUI

@main
struct VitalStrideApp: App {
    private let container: ModelContainer?
    private let containerError: String?

    init() {
        do {
            let modelContainer = try ModelContainerConfiguration.makeContainer()
            container = modelContainer
            containerError = nil
            ExerciseSeeder.seedIfNeeded(context: modelContainer.mainContext)
        } catch {
            container = nil
            containerError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView()
                    .modelContainer(container)
            } else {
                DataStoreErrorView(errorMessage: containerError ?? "Unknown error")
            }
        }
    }
}
