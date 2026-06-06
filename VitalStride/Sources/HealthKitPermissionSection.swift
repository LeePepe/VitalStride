import HealthKit
import HealthKitService
import SwiftUI

struct HealthKitPermissionSection: View {
    @State private var authorizationStatus: HKAuthorizationRequestStatus?
    @State private var isLoading = true
    @State private var isRequesting = false

    private let healthStore = HKHealthStore()

    private static let requestedTypes: [(String, String)] = [
        ("心率", "heart.fill"),
        ("步数", "figure.walk"),
        ("睡眠", "moon.fill"),
        ("训练记录", "figure.run"),
        ("活动能量", "flame.fill"),
        ("体重", "scalemass.fill"),
    ]

    private static let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
    ]

    private static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
    ]

    var body: some View {
        Section("HealthKit 权限") {
            HStack {
                Label("授权状态", systemImage: "heart.text.square")
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Text(statusText)
                        .foregroundStyle(statusColor)
                }
            }

            if authorizationStatus == .shouldRequest {
                Button {
                    Task { await requestAuthorization() }
                } label: {
                    HStack {
                        Label("请求授权", systemImage: "checkmark.shield")
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
                Label("管理 HealthKit 权限", systemImage: "arrow.up.right.square")
            }

            DisclosureGroup {
                ForEach(Self.requestedTypes, id: \.0) { name, icon in
                    Label(name, systemImage: icon)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("请求的数据类型", systemImage: "list.bullet")
            }
        }
        .task {
            await checkAuthorization()
        }
    }

    private var statusText: String {
        switch authorizationStatus {
        case .shouldRequest:
            return "待授权"
        case .unknown:
            return "未知"
        case .unnecessary:
            return "已请求授权"
        case .none:
            return "检查中…"
        @unknown default:
            return "未知"
        }
    }

    private var statusColor: Color {
        switch authorizationStatus {
        case .unnecessary:
            return .green
        case .shouldRequest:
            return .orange
        default:
            return .secondary
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
        do {
            try await healthStore.requestAuthorization(
                toShare: Self.shareTypes,
                read: Self.readTypes
            )
        } catch {}
        await checkAuthorization()
        isRequesting = false
        NotificationCenter.default.post(name: .healthKitAuthorizationChanged, object: nil)
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
}
