import DesignKit
import HealthKit
import HealthKitService
import SwiftUI
import TelemetryKit

struct HealthKitPermissionSection: View {
    @Environment(\.theme) private var theme
    @State private var authorizationStatus: HKAuthorizationRequestStatus?
    @State private var isLoading = true
    @State private var isRequesting = false

    private let healthStore = HKHealthStore()

    private static let requestedTypes: [(String, String)] = [
        (String(localized: "心率", comment: ""), "heart.fill"),
        (String(localized: "步数", comment: ""), "figure.walk"),
        (String(localized: "睡眠", comment: ""), "moon.fill"),
        (String(localized: "训练记录", comment: ""), "figure.run"),
        (String(localized: "活动能量", comment: ""), "flame.fill"),
        (String(localized: "体重", comment: ""), "scalemass.fill"),
        (String(localized: "基础代谢", comment: ""), "flame"),
        (String(localized: "步行+跑步距离", comment: ""), "figure.walk.motion"),
        (String(localized: "骑行距离", comment: ""), "bicycle"),
        (String(localized: "锻炼时间", comment: ""), "timer"),
        (String(localized: "站立时间", comment: ""), "figure.stand"),
        (String(localized: "已爬楼层", comment: ""), "figure.stairs"),
        (String(localized: "体脂率", comment: ""), "percent"),
        (String(localized: "去脂体重", comment: ""), "figure.arms.open"),
        (String(localized: "身高", comment: ""), "ruler"),
        ("BMI", "number"),
        (String(localized: "静息心率", comment: ""), "heart"),
        (String(localized: "心率变异性", comment: ""), "waveform.path.ecg"),
        (String(localized: "最大摄氧量", comment: ""), "lungs.fill"),
        (String(localized: "膳食能量", comment: ""), "fork.knife"),
        (String(localized: "蛋白质", comment: ""), "takeoutbag.and.cup.and.straw.fill"),
        (String(localized: "碳水化合物", comment: ""), "leaf.fill"),
        (String(localized: "脂肪", comment: ""), "drop.fill"),
        (String(localized: "饮水量", comment: ""), "cup.and.saucer.fill"),
    ]

    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
    ]

    private static var readTypes: Set<HKObjectType> {
        var types = HealthKitService.readTypes
        types.insert(HKObjectType.workoutType())
        return types
    }

    var body: some View {
        Section(String(localized: "HealthKit 权限", comment: "")) {
            HStack {
                Label(String(localized: "授权状态", comment: ""), systemImage: "heart.text.square")
                    .tint(theme.primary.primary)
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    StatusPill(statusText, tone: statusTone)
                }
            }

            if authorizationStatus == .shouldRequest {
                Button {
                    Task { await requestAuthorization() }
                } label: {
                    HStack {
                        Label(String(localized: "请求授权", comment: ""), systemImage: "checkmark.shield")
                        Spacer()
                        if isRequesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRequesting)
            }

            Button {
                openHealthSettings()
            } label: {
                Label(String(localized: "管理 HealthKit 权限", comment: ""), systemImage: "arrow.up.right.square")
            }

            DisclosureGroup {
                ForEach(Self.requestedTypes, id: \.0) { name, icon in
                    Label(name, systemImage: icon)
                        .font(.subheadline)
                        .foregroundStyle(theme.neutrals.text2)
                }
            } label: {
                Label(String(localized: "请求的数据类型", comment: ""), systemImage: "list.bullet")
                    .tint(theme.primary.primary)
            }
        }
        .task {
            await checkAuthorization()
        }
    }

    private var statusText: String {
        switch authorizationStatus {
        case .shouldRequest:
            return String(localized: "待授权", comment: "")
        case .unknown:
            return String(localized: "未知", comment: "")
        case .unnecessary:
            return String(localized: "已请求授权", comment: "")
        case .none:
            return String(localized: "检查中…", comment: "")
        @unknown default:
            return String(localized: "未知", comment: "")
        }
    }

    private var statusTone: PillTone {
        switch authorizationStatus {
        case .unnecessary:
            return .success
        case .shouldRequest:
            return .warning
        default:
            return .neutral
        }
    }

    private func checkAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            isLoading = false
            return
        }
        do {
            let status = try await healthStore.statusForAuthorizationRequest(
                toShare: Self.shareTypes,
                read: Self.readTypes
            )
            authorizationStatus = status
        } catch {
            authorizationStatus = .unknown
        }
        isLoading = false
    }

    private func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isRequesting = true
        var requestSucceeded = false
        do {
            try await healthStore.requestAuthorization(
                toShare: Self.shareTypes,
                read: Self.readTypes
            )
            requestSucceeded = true
        } catch {}
        await checkAuthorization()
        isRequesting = false
        NotificationCenter.default.post(name: .healthKitAuthorizationChanged, object: nil)
        // HealthKit deliberately hides read-denial; the strongest signal we can get
        // post-request is the share authorization on the requested write types. If
        // any requested share type is still not authorized after the prompt closed,
        // treat the consent as denied. (Request-API error also counts as denied.)
        let granted = requestSucceeded
            && Self.shareTypes.allSatisfy { healthStore.authorizationStatus(for: $0) == .sharingAuthorized }
        TelemetryService.shared.trackNonisolated(
            granted ? .healthKitAuthorized : .healthKitDenied
        )
    }

    private func openHealthSettings() {
        guard let url = URL(string: "x-apple-health://") else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }
}

#Preview {
    Form {
        HealthKitPermissionSection()
    }
    .designThemePreview()
}
