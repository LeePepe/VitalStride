import DesignKit
import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case workout = "训练"
    case data = "数据"
    case ai = "AI"
    case settings = "设置"

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

    var accessibilityName: String {
        switch self {
        case .overview: "概览"
        case .workout: "训练"
        case .data: "数据"
        case .ai: "AI 助手"
        case .settings: "设置"
        }
    }

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
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
                    .accessibilityLabel(section.accessibilityName)
            }
            .tint(theme.primary.primary)
            .navigationTitle("VitalStride")
        } detail: {
            if let section = selectedSection {
                section.detailView
            } else {
                Text("请选择一个功能区域")
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
