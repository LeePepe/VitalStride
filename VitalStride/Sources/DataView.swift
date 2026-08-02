// MY-1090: pre-existing `no_hardcoded_chinese` literals (section headers,
// row labels, a11y strings) predate the `--strict` SwiftLint hook and stay
// silenced at file scope until the shared i18n cleanup migrates them to
// Localizable.xcstrings. No semantic change from this pragma.
// swiftlint:disable no_hardcoded_chinese
import DesignKit
import HealthKitService
import os
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels

// MARK: - DataView

struct DataView: View {
    @State private var needsAuthorization = false
    @State private var isCheckingAuth = true
    @State private var authCheckToken = UUID()
    @State private var availableTypes: Set<HealthSampleType>?
    @State private var aiSummaryState = DataAISummaryState()
    @AppStorage(aiPrivacyConsentKey) private var aiPrivacyConsented = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.healthDataCache) private var healthDataCache
    @Environment(\.modelContext) private var modelContext
    @Environment(\.routingSignalStore) private var signalStore
    #if os(iOS)
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    #endif

    private let logger = Logger(subsystem: "com.vitalstride", category: "DataView")

    static let activityTypes: [HealthSampleType] = [
        .stepCount, .activeEnergyBurned, .basalEnergyBurned,
        .distanceWalkingRunning, .distanceCycling, .appleExerciseTime,
        .appleStandTime, .flightsClimbed,
    ]

    static let heartTypes: [HealthSampleType] = [
        .heartRate, .restingHeartRate, .heartRateVariabilitySDNN, .vo2Max,
    ]

    static let bodyTypes: [HealthSampleType] = [
        .bodyMass, .bodyFatPercentage, .leanBodyMass, .height, .bodyMassIndex,
    ]

    static let sleepTypes: [HealthSampleType] = [
        .sleepAnalysis,
    ]

    static let nutritionTypes: [HealthSampleType] = [
        .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates,
        .dietaryFatTotal, .dietaryWater,
    ]

    static let availableTypesProbeScope: Set<HealthSampleType> = Set(
        activityTypes + heartTypes + bodyTypes + sleepTypes + nutritionTypes
    )

    var body: some View {
        NavigationStack {
            List {
                if isCheckingAuth {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                                .accessibilityLabel(String(localized: "检查 HealthKit 授权状态", comment: "Auth check a11y"))
                            Spacer()
                        }
                    }
                } else if needsAuthorization {
                    authorizationCTASection
                } else if availableTypes == nil {
                    summarySection
                    aiSummarySection
                    typesLoadingSection
                    workoutSection
                } else {
                    summarySection
                    aiSummarySection
                    activitySection
                    heartSection
                    bodySection
                    sleepSection
                    nutritionSection
                    workoutSection
                }
            }
            .navigationTitle(String(localized: "数据", comment: "Data tab title"))
            .task(id: authCheckToken) {
                await checkAuthorizationStatus()
                if aiPrivacyConsented, let types = availableTypes, !types.isEmpty {
                    aiSummaryState.signalStore = signalStore
                    await aiSummaryState.loadIfNeeded(
                        availableTypes: types,
                        modelContainer: modelContext.container,
                        healthDataCache: healthDataCache
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthKitAuthorizationChanged)) { _ in
                authCheckToken = UUID()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, !isCheckingAuth {
                    authCheckToken = UUID()
                }
            }
            .onChange(of: isCheckingAuth) { _, newValue in
                if !newValue, !needsAuthorization {
                    AIDataAnalysisPreloader.pregenerateTopInterestsIfConsented(
                        modelContainer: modelContext.container,
                        healthDataCache: healthDataCache
                    )
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var aiSummarySection: some View {
        if aiPrivacyConsented, let types = availableTypes, !types.isEmpty {
            DataAISummaryCard(state: aiSummaryState)
        }
    }

    private var authorizationCTASection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(String(localized: "需要 HealthKit 授权", comment: ""))
                    .font(.headline)
                #if os(iOS)
                Text(String(
                    localized: "授权后即可查看心率、步数等健康数据。轻点下方按钮前往「设置」完成授权。",
                    comment: "iOS unauthorized HealthKit explanatory copy in DataView authorization CTA section"
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    navigation?.selectedTab = .settings
                } label: {
                    Label(
                        String(localized: "前往「设置」授权 HealthKit", comment: "Navigate to settings for HealthKit authorization"),
                        systemImage: "gearshape"
                    )
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(String(localized: "切换到设置页面以授权 HealthKit", comment: "HealthKit settings a11y hint"))
                #else
                Text(String(
                    localized: "请在侧边栏「设置」中授权访问健康数据，授权后即可查看心率、步数等数据。",
                    comment: "macOS unauthorized HealthKit explanatory copy in DataView authorization CTA section"
                ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .accessibilityElement(children: .contain)
        }
    }

    private var typesLoadingSection: some View {
        Section {
            HStack(spacing: 8) {
                Spacer()
                ProgressView()
                Text(String(localized: "正在检测可用数据…", comment: "Loading available data types"))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "正在检测可用数据类型", comment: "Loading available data types a11y"))
        }
    }

    private var summarySection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StepsSummaryCard()
                HeartRateSummaryCard()
                SleepSummaryCard()
                WeightSummaryCard()
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var activitySection: some View {
        if hasVisibleTypes(in: Self.activityTypes) {
            Section {
                if isAvailable(.stepCount) {
                    NavigationLink {
                        StepsDetailView()
                    } label: {
                        Label(String(localized: "步数", comment: "Steps"), systemImage: "figure.walk")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .stepCount) })
                }
                if isAvailable(.activeEnergyBurned) {
                    NavigationLink {
                        ActiveEnergyDetailView()
                    } label: {
                        Label(String(localized: "活动能量", comment: "Active energy"), systemImage: "flame.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .activeEnergyBurned) })
                }
                if isAvailable(.basalEnergyBurned) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .basalEnergyBurned)
                    } label: {
                        Label(String(localized: "基础代谢能量", comment: "Basal energy"), systemImage: "flame")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .basalEnergyBurned) })
                }
                if isAvailable(.distanceWalkingRunning) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .distanceWalkingRunning)
                    } label: {
                        Label(String(localized: "步行+跑步距离", comment: "Walking running distance"), systemImage: "figure.walk.motion")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .distanceWalkingRunning) })
                }
                if isAvailable(.distanceCycling) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .distanceCycling)
                    } label: {
                        Label(String(localized: "骑行距离", comment: "Cycling distance"), systemImage: "bicycle")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .distanceCycling) })
                }
                if isAvailable(.appleExerciseTime) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .appleExerciseTime)
                    } label: {
                        Label(String(localized: "锻炼时间", comment: "Exercise time"), systemImage: "figure.run")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .appleExerciseTime) })
                }
                if isAvailable(.appleStandTime) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .appleStandTime)
                    } label: {
                        Label(String(localized: "站立时间", comment: "Stand time"), systemImage: "figure.stand")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .appleStandTime) })
                }
                if isAvailable(.flightsClimbed) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .flightsClimbed)
                    } label: {
                        Label(String(localized: "已爬楼层", comment: "Flights climbed"), systemImage: "figure.stairs")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .flightsClimbed) })
                }
            } header: {
                Text("活动", comment: "Activity section header")
            }
        }
    }

    @ViewBuilder
    private var heartSection: some View {
        if hasVisibleTypes(in: Self.heartTypes) {
            Section {
                if isAvailable(.heartRate) {
                    NavigationLink {
                        HeartRateDetailView()
                    } label: {
                        Label(String(localized: "心率", comment: "Heart rate"), systemImage: "heart.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .heartRate) })
                }
                if isAvailable(.restingHeartRate) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .restingHeartRate)
                    } label: {
                        Label(String(localized: "静息心率", comment: "Resting heart rate"), systemImage: "heart")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .restingHeartRate) })
                }
                if isAvailable(.heartRateVariabilitySDNN) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .heartRateVariabilitySDNN)
                    } label: {
                        Label(String(localized: "心率变异性", comment: "Heart rate variability"), systemImage: "waveform.path.ecg")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .heartRateVariabilitySDNN) })
                }
                if isAvailable(.vo2Max) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .vo2Max)
                    } label: {
                        Label(String(localized: "最大摄氧量", comment: "VO2 Max"), systemImage: "lungs.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .vo2Max) })
                }
            } header: {
                Text("心脏", comment: "Heart section header")
            }
        }
    }

    @ViewBuilder
    private var bodySection: some View {
        if hasVisibleTypes(in: Self.bodyTypes) {
            Section {
                if isAvailable(.bodyMass) {
                    NavigationLink {
                        BodyWeightDetailView()
                    } label: {
                        Label(String(localized: "体重", comment: "Body weight"), systemImage: "scalemass.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .bodyMass) })
                }
                if isAvailable(.bodyFatPercentage) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .bodyFatPercentage)
                    } label: {
                        Label(String(localized: "体脂率", comment: "Body fat percentage"), systemImage: "percent")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .bodyFatPercentage) })
                }
                if isAvailable(.leanBodyMass) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .leanBodyMass)
                    } label: {
                        Label(String(localized: "去脂体重", comment: "Lean body mass"), systemImage: "scalemass")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .leanBodyMass) })
                }
                if isAvailable(.height) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .height)
                    } label: {
                        Label(String(localized: "身高", comment: "Height"), systemImage: "ruler")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .height) })
                }
                if isAvailable(.bodyMassIndex) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .bodyMassIndex)
                    } label: {
                        Label(String(localized: "BMI", comment: "Body mass index"), systemImage: "number")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .bodyMassIndex) })
                }
            } header: {
                Text("身体测量", comment: "Body measurements section header")
            }
        }
    }

    @ViewBuilder
    private var sleepSection: some View {
        if hasVisibleTypes(in: Self.sleepTypes) {
            Section {
                if isAvailable(.sleepAnalysis) {
                    NavigationLink {
                        SleepDetailView()
                    } label: {
                        Label(String(localized: "睡眠", comment: "Sleep"), systemImage: "bed.double.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .sleepAnalysis) })
                }
            } header: {
                Text("睡眠", comment: "Sleep section header")
            }
        }
    }

    @ViewBuilder
    private var nutritionSection: some View {
        if hasVisibleTypes(in: Self.nutritionTypes) {
            Section {
                if isAvailable(.dietaryEnergyConsumed) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .dietaryEnergyConsumed)
                    } label: {
                        Label(String(localized: "膳食能量摄入", comment: "Dietary energy"), systemImage: "fork.knife")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .dietaryEnergyConsumed) })
                }
                if isAvailable(.dietaryProtein) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .dietaryProtein)
                    } label: {
                        Label(String(localized: "蛋白质", comment: "Protein"), systemImage: "fish.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .dietaryProtein) })
                }
                if isAvailable(.dietaryCarbohydrates) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .dietaryCarbohydrates)
                    } label: {
                        Label(String(localized: "碳水化合物", comment: "Carbohydrates"), systemImage: "leaf.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .dietaryCarbohydrates) })
                }
                if isAvailable(.dietaryFatTotal) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .dietaryFatTotal)
                    } label: {
                        Label(String(localized: "脂肪", comment: "Fat"), systemImage: "drop.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .dietaryFatTotal) })
                }
                if isAvailable(.dietaryWater) {
                    NavigationLink {
                        GenericHealthDetailView(sampleType: .dietaryWater)
                    } label: {
                        Label(String(localized: "饮水量", comment: "Water"), systemImage: "drop.dewy.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded { recordTap(for: .dietaryWater) })
                }
            } header: {
                Text("营养", comment: "Nutrition section header")
            }
        }
    }

    private var workoutSection: some View {
        Section {
            NavigationLink {
                WorkoutHistoryView()
            } label: {
                Label(String(localized: "运动记录", comment: "Workout history"), systemImage: "figure.run.circle")
            }
        } header: {
            Text("运动", comment: "Workout section header")
        }
    }

    // MARK: - Filtering Helpers

    private func isAvailable(_ type: HealthSampleType) -> Bool {
        availableTypes?.contains(type) ?? false
    }

    private func hasVisibleTypes(in sectionTypes: [HealthSampleType]) -> Bool {
        guard let available = availableTypes else { return false }
        return sectionTypes.contains { available.contains($0) }
    }

    // MARK: - Auth & Available Types

    private func checkAuthorizationStatus() async {
        do {
            let status = try await healthKitService.authorizationStatus()
            if status == .shouldRequest {
                if !needsAuthorization {
                    await healthDataCache.handleAuthorizationRevoked()
                    healthKitService.clearAllAnchors()
                }
                needsAuthorization = true
            } else {
                let cachedTypes = await healthDataCache.cachedTypes()
                let accessProbeTypes = cachedTypes.isEmpty
                    ? Self.availableTypesProbeScope
                    : cachedTypes
                let hasAccess = await healthKitService.probeReadAccess(for: accessProbeTypes)
                if !hasAccess {
                    await healthDataCache.handleAuthorizationRevoked()
                    healthKitService.clearAllAnchors()
                    needsAuthorization = true
                } else {
                    needsAuthorization = false
                }
            }
        } catch {
            if !needsAuthorization {
                await healthDataCache.handleAuthorizationRevoked()
                healthKitService.clearAllAnchors()
            }
            needsAuthorization = true
        }

        if !needsAuthorization {
            availableTypes = await healthDataCache.getAvailableTypes()
        }

        isCheckingAuth = false

        if !needsAuthorization {
            await refreshAvailableTypesIfNeeded()
        }
    }

    private func refreshAvailableTypesIfNeeded() async {
        let isStale = await healthDataCache.isAvailableTypesStale()
        guard availableTypes == nil || isStale else {
            logVisibleSections()
            return
        }

        await healthDataCache.probeAndUpdateAvailableTypes(from: Self.availableTypesProbeScope)
        availableTypes = await healthDataCache.getAvailableTypes()
        logVisibleSections()
    }

    private func logVisibleSections() {
        guard let types = availableTypes else { return }
        let visibleTypeCount = types.count
        var sectionCount = 0
        if Self.activityTypes.contains(where: { types.contains($0) }) { sectionCount += 1 }
        if Self.heartTypes.contains(where: { types.contains($0) }) { sectionCount += 1 }
        if Self.bodyTypes.contains(where: { types.contains($0) }) { sectionCount += 1 }
        if Self.sleepTypes.contains(where: { types.contains($0) }) { sectionCount += 1 }
        if Self.nutritionTypes.contains(where: { types.contains($0) }) { sectionCount += 1 }
        logger.info("DataView showing \(visibleTypeCount) types in \(sectionCount) sections")
    }

    // MARK: - User Interest

    private func recordTap(for sampleType: HealthSampleType) {
        if let identifier = TelemetryIdentifier(validating: sampleType.rawValue) {
            TelemetryService.shared.trackNonisolated(.dataDetailOpened(sampleType: identifier))
        }
        let container = modelContext.container
        Task.detached {
            let context = ModelContext(container)
            UserInterestTracker.recordTap(for: sampleType, in: context)
        }
    }
}

// MARK: - Section Card Container

struct DataSectionCard<Destination: View, Content: View>: View {
    let title: String
    let systemImage: String
    let destination: Destination
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationLink {
            destination
        } label: {
            Card {
                Label(title, systemImage: systemImage)
                    .font(TypeScale.title)

                content()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "轻点查看详情", comment: "Card navigation a11y hint"))
    }
}

#Preview {
    DataView()
        .designThemePreview()
}
