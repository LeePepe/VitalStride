// swiftlint:disable no_hardcoded_chinese
// MY-1269: Chinese string values are xcstrings source keys resolved via
// String(localized:). Rule silenced at file scope pending ASCII-key migration.
import DesignKit
import SwiftUI

struct WatchContentView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    Text("力量训练 — Coming Soon")
                        .font(.headline)
                        .foregroundStyle(theme.neutrals.text2)
                } label: {
                    Label("开始训练", systemImage: "dumbbell.fill")
                        .tint(theme.primary.primary)
                }
                .accessibilityLabel(String(localized: "开始训练", comment: "Start workout a11y (watch)"))
            }
            .navigationTitle("VitalStride")
        }
    }
}

#Preview {
    WatchContentView()
        .designThemePreview()
}
