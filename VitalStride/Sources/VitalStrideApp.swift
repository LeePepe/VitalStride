import SwiftData
import SwiftUI

@main
struct VitalStrideApp: App {
    private let container: ModelContainer?
    private let containerError: String?

    init() {
        do {
            container = try ModelContainerConfiguration.makeContainer()
            containerError = nil
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
