import SwiftUI

struct MacOverviewPlaceholder: View {
    var body: some View {
        Text("概览 — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacWorkoutPlaceholder: View {
    var body: some View {
        Text("训练 — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacDataPlaceholder: View {
    var body: some View {
        Text("数据 — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacAIPlaceholder: View {
    var body: some View {
        Text("AI — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacSettingsPlaceholder: View {
    var body: some View {
        Text("设置 — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("概览") { MacOverviewPlaceholder() }
#Preview("训练") { MacWorkoutPlaceholder() }
#Preview("数据") { MacDataPlaceholder() }
#Preview("AI") { MacAIPlaceholder() }
#Preview("设置") { MacSettingsPlaceholder() }
