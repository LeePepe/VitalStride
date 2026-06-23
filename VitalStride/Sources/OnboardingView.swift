import HealthKit
import HealthKitService
import SwiftUI
import TelemetryKit

struct OnboardingView: View {
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

            Button("跳过") {
                completeOnboarding()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.walk.motion")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("VitalStride")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("你的健康数据 + AI 分析助手")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            swipeHint
        }
        .padding(.horizontal, 32)
    }

    private var featuresPage: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("核心功能")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 24) {
                featureRow(
                    icon: "dumbbell.fill",
                    title: "训练记录",
                    description: "记录力量训练，追踪每组重量和次数"
                )
                featureRow(
                    icon: "heart.text.square.fill",
                    title: "健康数据",
                    description: "心率、步数、睡眠、体重、活动能量一目了然"
                )
                featureRow(
                    icon: "brain",
                    title: "AI 分析",
                    description: "智能分析训练数据，提供个性化建议"
                )
            }

            Spacer()

            swipeHint
        }
        .padding(.horizontal, 32)
    }

    private var healthKitPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.pink)

            Text("连接健康数据")
                .font(.title2)
                .fontWeight(.bold)

            Text("VitalStride 需要访问你的健康数据来展示心率、步数等信息，并将训练记录写入 HealthKit。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                Task { await requestHealthKitAuthorization() }
            } label: {
                HStack {
                    if isRequestingAuth {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("授权 HealthKit")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequestingAuth)

            Button("稍后再说") {
                completeOnboarding()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Components

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var swipeHint: some View {
        Text("左滑继续")
            .font(.footnote)
            .foregroundStyle(.tertiary)
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
}
