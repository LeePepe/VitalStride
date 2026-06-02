import SwiftData
import SwiftUI

@main
struct VitalStrideApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(try! ModelContainerConfiguration.makeContainer())
    }
}
