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
                .accessibilityLabel("开始训练")
            }
            .navigationTitle("VitalStride")
        }
    }
}

#Preview {
    WatchContentView()
        .designThemePreview()
}
