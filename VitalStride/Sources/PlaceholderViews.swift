// Pre-existing `no_hardcoded_chinese` literals (placeholder copy, preview titles)
// predate the strict SwiftLint baseline and are silenced at file scope until the
// shared i18n cleanup migrates them to Localizable.xcstrings. DataView.swift precedent.
// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftUI

struct OverviewPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text(String(localized: "概览 — Coming Soon", comment: ""))
            .font(.title)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct WorkoutPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text(String(localized: "训练 — Coming Soon", comment: ""))
            .font(.title)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

struct DataPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text(String(localized: "数据 — Coming Soon", comment: ""))
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
        Text(String(localized: "设置 — Coming Soon", comment: ""))
            .font(.title)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.neutrals.bg)
    }
}

#Preview(String(localized: "概览", comment: "")) { OverviewPlaceholder().designThemePreview() }
#Preview(String(localized: "训练", comment: "")) { WorkoutPlaceholder().designThemePreview() }
#Preview(String(localized: "数据", comment: "")) { DataPlaceholder().designThemePreview() }
#Preview("AI") { AIPlaceholder().designThemePreview() }
#Preview(String(localized: "设置", comment: "")) { SettingsPlaceholder().designThemePreview() }
