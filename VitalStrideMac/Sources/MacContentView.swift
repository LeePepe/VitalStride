// swiftlint:disable no_hardcoded_chinese
// Rationale: All CJK literals in this file are wrapped in String(localized:) for i18n;
// the regex-based rule can't distinguish that from a raw literal (MY-1269).
import AIService
import DesignKit
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "overview"
    case workout = "workout"
    case data = "data"
    case ai = "ai"
    case settings = "settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "chart.bar.fill"
        case .workout: "dumbbell.fill"
        case .data: "heart.text.square.fill"
        case .ai: "brain"
        case .settings: "gearshape.fill"
        }
    }

    /// Localized display name shown in the sidebar list and used as the a11y label.
    var displayName: String {
        switch self {
        case .overview: String(localized: "概览", comment: "Sidebar section: Overview")
        case .workout: String(localized: "训练", comment: "Sidebar section: Workouts")
        case .data: String(localized: "数据", comment: "Sidebar section: Data")
        case .ai: String(localized: "AI 助手", comment: "Sidebar section: AI assistant")
        case .settings: String(localized: "设置", comment: "Sidebar section: Settings")
        }
    }

    var accessibilityName: String { displayName }

    @ViewBuilder
    var detailView: some View {
        switch self {
        case .overview: MacHolisticOverview()
        case .workout: MacWorkoutPlaceholder()
        case .data: DataView()
        case .ai: AIView()
        case .settings: MacSettingsPlaceholder()
        }
    }
}

private struct MacHolisticOverview: View {
    var body: some View {
        ScrollView {
            FourLayerSummaryDashboard(report: Self.previewReport())
                .padding(Space.lg)
                .frame(maxWidth: Space.contentMaxWidth, alignment: .leading)
        }
        .navigationTitle(String(localized: "概览", comment: "macOS overview title"))
    }

    private static func previewReport() -> AIService.HolisticFourLayerReport {
        AIService.HolisticFourLayerReport(
            l1: [
                .init(domain: .heart, metric: "hrvCurrent", value: 68, message: "Observed aggregate"),
                .init(domain: .heart, metric: "hrv7d", value: 65, message: "Observed aggregate"),
                .init(domain: .sleep, metric: "sleepEfficiency", value: 0.92, message: "Observed aggregate"),
                .init(domain: .trainingLoad, metric: "acwr", value: 0.9, message: "Observed aggregate"),
                .init(domain: .aerobic, metric: "vo2Max", value: 51.4, message: "Observed aggregate"),
                .init(domain: .neat, metric: "nonWorkoutSteps", value: 7680, message: "Observed aggregate")
            ],
            l2: [
                .init(primaryDomain: .sleep, secondaryDomain: .trainingLoad, relationship: "sleepTrainingCoupling", message: String(localized: "mac_overview_sleep_load_message", defaultValue: "Sleep and training load remain compatible.", comment: "macOS preview coupling message"), severity: .normal),
                .init(primaryDomain: .neat, secondaryDomain: .heart, relationship: "stepsBodyCoupling", message: String(localized: "mac_overview_steps_body_message", defaultValue: "Movement supports active recovery.", comment: "macOS preview coupling message"), severity: .normal)
            ],
            l3: .init(readinessScore: 82, autonomicScore: 84, sleepRestorationScore: 79, fatigueBalanceScore: 83, mesocyclePhase: .intensification, recommendedIntensityCap: 0.85),
            l4: .init(
                northStarScore: 86,
                directive: String(localized: "mac_overview_directive", defaultValue: "Recovery and movement support controlled training today.", comment: "macOS preview directive"),
                prioritizedActions: [
                    String(localized: "mac_overview_action_controlled", defaultValue: "Keep the planned session controlled.", comment: "macOS preview action"),
                    String(localized: "mac_overview_action_sleep", defaultValue: "Protect a consistent sleep opportunity.", comment: "macOS preview action"),
                    String(localized: "mac_overview_action_movement", defaultValue: "Use easy movement breaks.", comment: "macOS preview action")
                ]
            )
        )
    }
}

struct MacContentView: View {
    @Environment(\.theme) private var theme
    @State private var selectedSection: SidebarSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                Label(section.displayName, systemImage: section.icon)
                    .tag(section)
                    .accessibilityLabel(section.accessibilityName)
            }
            .tint(theme.primary.primary)
            .navigationTitle("VitalStride")
        } detail: {
            if let section = selectedSection {
                section.detailView
            } else {
                Text(String(localized: "请选择一个功能区域", comment: ""))
                    .font(TypeScale.title)
                    .foregroundStyle(theme.neutrals.text2)
            }
        }
    }
}

#Preview {
    MacContentView()
        .designThemePreview()
}
