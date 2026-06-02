import SwiftData
import SwiftUI

@main
struct VitalStrideWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
        .modelContainer(try! ModelContainerConfiguration.makeContainer())
    }
}
