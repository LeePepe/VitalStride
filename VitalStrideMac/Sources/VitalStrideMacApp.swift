import SwiftData
import SwiftUI

@main
struct VitalStrideMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacContentView()
        }
        .modelContainer(try! ModelContainerConfiguration.makeContainer())
    }
}
