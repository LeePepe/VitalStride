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
        case .overview: MacOverviewPlaceholder()
        case .workout: MacWorkoutPlaceholder()
        case .data: DataView()
        case .ai: AIView()
        case .settings: MacSettingsPlaceholder()
        }
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
