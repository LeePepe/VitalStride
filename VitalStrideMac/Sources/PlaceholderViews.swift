// Pre-existing `no_hardcoded_chinese` literals (placeholder copy, preview titles)
// predate the strict SwiftLint baseline and are silenced at file scope until the
// shared i18n cleanup migrates them to Localizable.xcstrings. DataView.swift precedent.
// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftUI

struct MacOverviewPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("概览 — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct MacWorkoutPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("训练 — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct MacDataPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("数据 — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct MacAIPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("AI — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct MacSettingsPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("设置 — Coming Soon")
            .font(.largeTitle)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

#Preview("概览") { MacOverviewPlaceholder().designThemePreview() }
#Preview("训练") { MacWorkoutPlaceholder().designThemePreview() }
#Preview("数据") { MacDataPlaceholder().designThemePreview() }
#Preview("AI") { MacAIPlaceholder().designThemePreview() }
#Preview("设置") { MacSettingsPlaceholder().designThemePreview() }
