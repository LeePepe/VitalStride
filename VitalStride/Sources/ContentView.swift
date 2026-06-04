import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("概览", systemImage: "chart.bar.fill") {
                OverviewView()
            }
            .accessibilityLabel("概览")

            Tab("训练", systemImage: "dumbbell.fill") {
                WorkoutListView()
            }
            .accessibilityLabel("训练")

            Tab("数据", systemImage: "heart.text.square.fill") {
                DataPlaceholder()
            }
            .accessibilityLabel("数据")

            Tab("AI", systemImage: "brain") {
                AIPlaceholder()
            }
            .accessibilityLabel("AI 助手")

            Tab("设置", systemImage: "gearshape.fill") {
                SettingsPlaceholder()
            }
            .accessibilityLabel("设置")
        }
    }
}

#Preview {
    ContentView()
}
