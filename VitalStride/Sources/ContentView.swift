import SwiftUI
import TelemetryKit
import VitalModels

enum AppTab: Hashable {
    // swiftlint:disable:next identifier_name
    case overview, workout, data, ai, settings
}

@Observable
final class AppNavigation {
    var selectedTab = AppTab.overview
    /// Set by `CrashRecoveryModifier` when the user chooses "恢复训练".
    /// `WorkoutListView` observes this, opens `ActiveWorkoutView` in resume
    /// mode, and clears it back to `nil`.
    var crashRecoveryResume: Workout?
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
        .detectsCrashRecovery(navigation: navigation)
        .onChange(of: nav.selectedTab) { _, newTab in
            TelemetryService.shared.trackNonisolated(
                .tabSwitched(tab: TelemetryHelpers.tabIdentifier(newTab))
            )
        }
    }
}

#Preview {
    ContentView()
}
