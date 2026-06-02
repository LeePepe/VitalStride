import SwiftData
import SwiftUI

@main
struct VitalStrideWatchApp: App {
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
            WatchContentView()
        }
        .modelContainer(container)
    }
}
