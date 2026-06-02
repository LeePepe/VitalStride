import SwiftUI

struct MacContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Label("Overview", systemImage: "heart.text.clipboard")
                Label("Workout", systemImage: "figure.strengthtraining.traditional")
                Label("Data", systemImage: "chart.xyaxis.line")
                Label("AI", systemImage: "brain")
                Label("Settings", systemImage: "gearshape")
            }
            .navigationTitle("VitalStride")
        } detail: {
            Text("Select a section")
        }
    }
}

#Preview {
    MacContentView()
}
