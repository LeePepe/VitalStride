import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case workout = "Workout"
    case data = "Data"
    case ai = "AI"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: "heart.text.clipboard"
        case .workout: "figure.strengthtraining.traditional"
        case .data: "chart.xyaxis.line"
        case .ai: "brain"
        case .settings: "gearshape"
        }
    }
}

struct MacContentView: View {
    @State private var selectedSection: SidebarSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationTitle("VitalStride")
        } detail: {
            if let section = selectedSection {
                Text(section.rawValue)
                    .font(.largeTitle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a section")
            }
        }
    }
}

#Preview {
    MacContentView()
}
