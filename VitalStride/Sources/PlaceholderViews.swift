// Pre-existing `no_hardcoded_chinese` literals (placeholder copy, preview titles)
// predate the strict SwiftLint baseline and are silenced at file scope until the
// shared i18n cleanup migrates them to Localizable.xcstrings. DataView.swift precedent.
// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftUI

struct OverviewPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("概览 — Coming Soon")
            .font(.title)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct WorkoutPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("训练 — Coming Soon")
            .font(.title)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct DataPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("数据 — Coming Soon")
            .font(.title)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct AIPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("AI — Coming Soon")
            .font(.title)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct SettingsPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("设置 — Coming Soon")
            .font(.title)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

#Preview("概览") { OverviewPlaceholder().designThemePreview() }
#Preview("训练") { WorkoutPlaceholder().designThemePreview() }
#Preview("数据") { DataPlaceholder().designThemePreview() }
#Preview("AI") { AIPlaceholder().designThemePreview() }
#Preview("设置") { SettingsPlaceholder().designThemePreview() }
