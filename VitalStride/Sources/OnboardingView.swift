// swiftlint:disable no_hardcoded_chinese
// Rationale: All CJK literals in this file are wrapped in String(localized:) for i18n;
// the regex-based rule can't distinguish that from a raw literal (MY-1269).
import DesignKit
import HealthKit
import HealthKitService
import SwiftUI
import TelemetryKit

struct OnboardingView: View {
    @Environment(\.theme) private var theme
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var isRequestingAuth = false

    private let healthStore = HKHealthStore()

    static var shareTypes: Set<HKSampleType> {
        #if os(iOS)
        [HKObjectType.workoutType()]
        #else
        []
        #endif
    }

    static var readTypes: Set<HKObjectType> {
        var types = HealthKitService.readTypes
        types.insert(HKObjectType.workoutType())
        return types
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                featuresPage.tag(1)
                healthKitPage.tag(2)
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #endif

            Button(String(localized: "跳过", comment: "")) {
                completeOnboarding()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .foregroundStyle(theme.neutrals.text2)
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.walk.motion")
                .font(.system(size: 80))
                .foregroundStyle(theme.primary.primary)

            Text("VitalStride")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(String(localized: "你的健康数据 + AI 分析助手", comment: ""))
                .font(.title3)
                .foregroundStyle(theme.neutrals.text2)
                .multilineTextAlignment(.center)

            Spacer()

            nextPageButton
            swipeHint
        }
        .padding(.horizontal, 32)
    }

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(String(localized: "核心功能", comment: ""))
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 24) {
                featureRow(
                    icon: "dumbbell.fill",
                    title: String(localized: "训练记录", comment: ""),
                    description: String(localized: "记录力量训练，追踪每组重量和次数", comment: "")
                )
                featureRow(
                    icon: "heart.text.square.fill",
                    title: String(localized: "健康数据", comment: ""),
                    description: String(localized: "心率、步数、睡眠、体重、活动能量一目了然", comment: "")
                )
                featureRow(
                    icon: "brain",
                    title: String(localized: "AI 分析", comment: ""),
                    description: String(localized: "智能分析训练数据，提供个性化建议", comment: "")
                )
            }

            Spacer()

            nextPageButton
            swipeHint
        }
        .padding(.horizontal, 32)
    }

    private var healthKitPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(theme.primary.primary)

            Text(String(localized: "连接健康数据", comment: ""))
                .font(.title2)
                .fontWeight(.bold)

            Text(String(localized: "VitalStride 需要访问你的健康数据来展示心率、步数等信息，并将训练记录写入 HealthKit。", comment: ""))
                .font(.body)
                .foregroundStyle(theme.neutrals.text2)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                Task { await requestHealthKitAuthorization() }
            } label: {
                HStack {
                    if isRequestingAuth {
                        ProgressView()
                            .tint(theme.primary.onPrimary)
                    }
                    Text(String(localized: "授权 HealthKit", comment: ""))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.primary.primary)
            .disabled(isRequestingAuth)

            Button(String(localized: "稍后再说", comment: "")) {
                completeOnboarding()
            }
            .foregroundStyle(theme.neutrals.text2)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Components

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(theme.primary.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
            }
        }
    }

    private var nextPageButton: some View {
        Button {
            withAnimation { currentPage += 1 }
        } label: {
            Text(String(localized: "onboarding_next_button"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.primary.primary)
    }

    private var swipeHint: some View {
        Text(String(localized: "左滑继续", comment: ""))
            .font(.footnote)
            .foregroundStyle(theme.neutrals.text3)
            .padding(.bottom, 60)
    }

    // MARK: - Actions

    private func requestHealthKitAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            completeOnboarding()
            return
        }

        isRequestingAuth = true
        var requestSucceeded = false
        do {
            try await healthStore.requestAuthorization(
                toShare: Self.shareTypes,
                read: Self.readTypes
            )
            requestSucceeded = true
        } catch {}
        isRequestingAuth = false
        NotificationCenter.default.post(name: .healthKitAuthorizationChanged, object: nil)

        // HealthKit hides read denial post-prompt; the strongest signal we have is
        // the share authorization on the requested write types. Treat any missing
        // share authorization (or a thrown request) as denied for telemetry purposes.
        let granted = requestSucceeded
            && Self.shareTypes.allSatisfy { healthStore.authorizationStatus(for: $0) == .sharingAuthorized }
        TelemetryService.shared.trackNonisolated(
            granted ? .healthKitAuthorized : .healthKitDenied
        )

        completeOnboarding()
    }

    private func completeOnboarding() {
        let wasAlreadyCompleted = hasCompletedOnboarding
        hasCompletedOnboarding = true
        if !wasAlreadyCompleted {
            TelemetryService.shared.trackNonisolated(.onboardingCompleted)
        }
    }
}

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .designThemePreview()
}
