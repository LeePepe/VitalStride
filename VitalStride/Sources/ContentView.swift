// swiftlint:disable no_hardcoded_chinese
// MY-1269: Chinese string values are the xcstrings *source keys* that get
// resolved through Localizable.xcstrings via String(localized:) — that is the
// intended flow, not a hardcoded literal. Rule stays silenced at file scope
// until we migrate to ASCII key IDs (tracked in the follow-up i18n sub-issue).
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
            .accessibilityLabel(String(localized: "概览", comment: "Overview tab a11y label"))

            Tab("训练", systemImage: "dumbbell.fill", value: .workout) {
                WorkoutListView()
            }
            .accessibilityLabel(String(localized: "训练", comment: "Workouts tab a11y label"))

            Tab("数据", systemImage: "heart.text.square.fill", value: .data) {
                DataView()
            }
            .accessibilityLabel(String(localized: "数据", comment: "Data tab a11y label"))

            Tab("AI", systemImage: "brain", value: .ai) {
                AIView()
            }
            .accessibilityLabel(String(localized: "AI 助手", comment: "AI assistant tab a11y label"))

            Tab("设置", systemImage: "gearshape.fill", value: .settings) {
                SettingsView()
            }
            .accessibilityLabel(String(localized: "设置", comment: "Settings tab a11y label"))
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
