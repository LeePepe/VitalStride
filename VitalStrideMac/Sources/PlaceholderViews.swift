// Pre-existing `no_hardcoded_chinese` literals (placeholder copy, preview titles)
// predate the strict SwiftLint baseline and are silenced at file scope until the
// shared i18n cleanup migrates them to Localizable.xcstrings. DataView.swift precedent.
// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftUI

struct MacOverviewPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text(String(localized: "概览 — Coming Soon", comment: ""))
            .font(.largeTitle)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct MacWorkoutPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text(String(localized: "训练 — Coming Soon", comment: ""))
            .font(.largeTitle)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct MacDataPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text(String(localized: "数据 — Coming Soon", comment: ""))
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
        Text(String(localized: "设置 — Coming Soon", comment: ""))
            .font(.largeTitle)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

#Preview(String(localized: "概览", comment: "")) { MacOverviewPlaceholder().designThemePreview() }
#Preview(String(localized: "训练", comment: "")) { MacWorkoutPlaceholder().designThemePreview() }
#Preview(String(localized: "数据", comment: "")) { MacDataPlaceholder().designThemePreview() }
#Preview("AI") { MacAIPlaceholder().designThemePreview() }
#Preview(String(localized: "设置", comment: "")) { MacSettingsPlaceholder().designThemePreview() }
