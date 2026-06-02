import SwiftUI

struct WatchContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    Text("力量训练 — Coming Soon")
                        .font(.headline)
                } label: {
                    Label("开始训练", systemImage: "dumbbell.fill")
                }
                .accessibilityLabel("开始训练")
            }
            .navigationTitle("VitalStride")
        }
    }
}

#Preview {
    WatchContentView()
}
