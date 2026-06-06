import SwiftUI

enum AppTab: Hashable {
    case overview, workout, data, ai, settings
}

@Observable
final class AppNavigation {
    var selectedTab = AppTab.overview
}

struct ContentView: View {
    @State private var navigation = AppNavigation()

    var body: some View {
        @Bindable var nav = navigation
        TabView(selection: $nav.selectedTab) {
            Tab("概览", systemImage: "chart.bar.fill", value: .overview) {
                OverviewView()
            }
            .accessibilityLabel("概览")

            Tab("训练", systemImage: "dumbbell.fill", value: .workout) {
                WorkoutListView()
            }
            .accessibilityLabel("训练")

            Tab("数据", systemImage: "heart.text.square.fill", value: .data) {
                DataView()
            }
            .accessibilityLabel("数据")

            Tab("AI", systemImage: "brain", value: .ai) {
                AIView()
            }
            .accessibilityLabel("AI 助手")

            Tab("设置", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
            .accessibilityLabel("设置")
        }
        .environment(navigation)
    }
}

#Preview {
    ContentView()
}
