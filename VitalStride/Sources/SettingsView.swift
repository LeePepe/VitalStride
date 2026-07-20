// swiftlint:disable no_hardcoded_chinese
// MY-1269: Chinese string values are xcstrings source keys resolved via
// String(localized:). Rule silenced at file scope pending ASCII-key migration.
import DesignKit
import HealthKitService
import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.healthKitService) private var healthKitService

    var body: some View {
        NavigationStack {
            Form {
                HealthKitPermissionSection()
                UnitPreferencesSection()
                trainingSection
                DataImportExportSection()
                AISettingsSection()
                aboutSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(String(localized: "设置", comment: "Nav title"))
        }
    }

    private var trainingSection: some View {
        Section(String(localized: "训练", comment: "Settings section: training")) {
            NavigationLink {
                WatchScreenSettingsView(pusher: makeWatchScreenConfigPusher())
            } label: {
                Label(
                    String(
                        localized: "settings.watchScreen.title",
                        comment: "Settings entry: iOS Settings → Training → Watch in-workout screen"
                    ),
                    systemImage: "applewatch"
                )
                .tint(theme.primary.primary)
            }
        }
    }

    /// Wire the environment `HealthKitService` into a
    /// `WatchScreenConfigPusher` so the settings view only depends on the
    /// injectable seam. The manager is created lazily inside the closure
    /// so we don't pay for `WCSession` setup unless the user actually
    /// changes a toggle.
    private func makeWatchScreenConfigPusher() -> WatchScreenConfigPusher {
        let service = healthKitService
        return { config in
            let manager = service.makeWorkoutSessionManager()
            await manager.updateWatchScreenConfig(config)
        }
    }

    private var aboutSection: some View {
        Section(String(localized: "关于", comment: "")) {
            HStack {
                Label(String(localized: "版本", comment: ""), systemImage: "info.circle")
                    .tint(theme.primary.primary)
                Spacer()
                Text(appVersion)
                    .font(TypeScale.num)
                    .monospacedDigit()
                    .foregroundStyle(theme.neutrals.text2)
            }

            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label(String(localized: "开源协议与致谢", comment: ""), systemImage: "doc.text")
                    .tint(theme.primary.primary)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct AcknowledgementsView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            Section {
                Text(String(localized: "VitalStride 使用了以下开源技术和框架：", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
            }

            Section("Apple Frameworks") {
                acknowledgementRow("SwiftUI", description: String(localized: "用户界面框架", comment: ""))
                acknowledgementRow("SwiftData", description: String(localized: "数据持久化", comment: ""))
                acknowledgementRow("HealthKit", description: String(localized: "健康数据访问", comment: ""))
                acknowledgementRow("Swift Charts", description: String(localized: "数据可视化", comment: ""))
                acknowledgementRow("CloudKit", description: String(localized: "跨设备同步", comment: ""))
            }
        }
        .navigationTitle(String(localized: "致谢", comment: "Nav title"))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func acknowledgementRow(_ name: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.body)
            Text(description)
                .font(.caption)
                .foregroundStyle(theme.neutrals.text2)
        }
    }
}

#Preview {
    SettingsView()
        .designThemePreview()
}

#Preview(String(localized: "致谢", comment: "")) {
    NavigationStack {
        AcknowledgementsView()
    }
    .designThemePreview()
}
