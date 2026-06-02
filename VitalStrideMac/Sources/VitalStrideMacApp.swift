import SwiftData
import SwiftUI

@main
struct VitalStrideMacApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainerConfiguration.makeContainer()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MacContentView()
        }
        .modelContainer(container)
    }
}
