import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            Form {
                HealthKitPermissionSection()
                UnitPreferencesSection()
                DataImportExportSection()
                aboutSection
            }
            .navigationTitle("设置")
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Label("版本", systemImage: "info.circle")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                AcknowledgementsView()
            } label: {
                Label("开源协议与致谢", systemImage: "doc.text")
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
    var body: some View {
        List {
            Section {
                Text("VitalStride 使用了以下开源技术和框架：")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Frameworks") {
                acknowledgementRow("SwiftUI", description: "用户界面框架")
                acknowledgementRow("SwiftData", description: "数据持久化")
                acknowledgementRow("HealthKit", description: "健康数据访问")
                acknowledgementRow("Swift Charts", description: "数据可视化")
                acknowledgementRow("CloudKit", description: "跨设备同步")
            }
        }
        .navigationTitle("致谢")
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
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}

#Preview("致谢") {
    NavigationStack {
        AcknowledgementsView()
    }
}
