import SwiftUI

struct OverviewPlaceholder: View {
    var body: some View {
        Text("概览 — Coming Soon")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkoutPlaceholder: View {
    var body: some View {
        Text("训练 — Coming Soon")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DataPlaceholder: View {
    var body: some View {
        Text("数据 — Coming Soon")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AIPlaceholder: View {
    var body: some View {
        Text("AI — Coming Soon")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsPlaceholder: View {
    var body: some View {
        Text("设置 — Coming Soon")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("概览") { OverviewPlaceholder() }
#Preview("训练") { WorkoutPlaceholder() }
#Preview("数据") { DataPlaceholder() }
#Preview("AI") { AIPlaceholder() }
#Preview("设置") { SettingsPlaceholder() }
