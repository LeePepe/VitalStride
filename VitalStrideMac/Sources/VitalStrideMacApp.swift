import SwiftData
import SwiftUI

@main
struct VitalStrideMacApp: App {
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
                MacContentView()
                    .modelContainer(container)
            } else {
                DataStoreErrorView(errorMessage: containerError ?? "Unknown error")
            }
        }
    }
}
