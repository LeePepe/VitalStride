import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Overview", systemImage: "heart.text.clipboard") {
                Text("Overview")
            }
            Tab("Workout", systemImage: "figure.strengthtraining.traditional") {
                Text("Workout")
            }
            Tab("Data", systemImage: "chart.xyaxis.line") {
                Text("Data")
            }
            Tab("AI", systemImage: "brain") {
                Text("AI")
            }
            Tab("Settings", systemImage: "gearshape") {
                Text("Settings")
            }
        }
    }
}

#Preview {
    ContentView()
}
