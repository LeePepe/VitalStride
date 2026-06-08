import HealthKitService
import SwiftUI
import VitalModels
import os

// MARK: - DataView

struct DataView: View {
    @State private var needsAuthorization = false
    @State private var isCheckingAuth = true
    @State private var authCheckToken = UUID()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.healthKitService) private var healthKitService
    @Environment(\.healthDataCache) private var healthDataCache

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
                } else {
                    summarySection
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
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthKitAuthorizationChanged)) { _ in
                authCheckToken = UUID()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, !isCheckingAuth {
                    authCheckToken = UUID()
                }
            }
        }
    }

    private var authorizationCTASection: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("需要 HealthKit 授权")
                    .font(.headline)
                Text("请前往设置页面授权访问健康数据，授权后即可查看心率、步数等数据。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .accessibilityElement(children: .combine)
        }
    }

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
                if !cachedTypes.isEmpty {
                    let hasAccess = await healthKitService.probeReadAccess(for: cachedTypes)
                    if !hasAccess {
                        await healthDataCache.handleAuthorizationRevoked()
                        healthKitService.clearAllAnchors()
                        needsAuthorization = true
                    } else {
                        needsAuthorization = false
                    }
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
        isCheckingAuth = false
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

    private var activitySection: some View {
        Section {
            NavigationLink {
                StepsDetailView()
            } label: {
                Label(String(localized: "步数", comment: "Steps"), systemImage: "figure.walk")
            }
            NavigationLink {
                ActiveEnergyDetailView()
            } label: {
                Label(String(localized: "活动能量", comment: "Active energy"), systemImage: "flame.fill")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .basalEnergyBurned)
            } label: {
                Label(String(localized: "基础代谢能量", comment: "Basal energy"), systemImage: "flame")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .distanceWalkingRunning)
            } label: {
                Label(String(localized: "步行+跑步距离", comment: "Walking running distance"), systemImage: "figure.walk.motion")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .distanceCycling)
            } label: {
                Label(String(localized: "骑行距离", comment: "Cycling distance"), systemImage: "bicycle")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .appleExerciseTime)
            } label: {
                Label(String(localized: "锻炼时间", comment: "Exercise time"), systemImage: "figure.run")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .appleStandTime)
            } label: {
                Label(String(localized: "站立时间", comment: "Stand time"), systemImage: "figure.stand")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .flightsClimbed)
            } label: {
                Label(String(localized: "已爬楼层", comment: "Flights climbed"), systemImage: "figure.stairs")
            }
        } header: {
            Text("活动", comment: "Activity section header")
        }
    }

    private var heartSection: some View {
        Section {
            NavigationLink {
                HeartRateDetailView()
            } label: {
                Label(String(localized: "心率", comment: "Heart rate"), systemImage: "heart.fill")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .restingHeartRate)
            } label: {
                Label(String(localized: "静息心率", comment: "Resting heart rate"), systemImage: "heart")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .heartRateVariabilitySDNN)
            } label: {
                Label(String(localized: "心率变异性", comment: "Heart rate variability"), systemImage: "waveform.path.ecg")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .vo2Max)
            } label: {
                Label(String(localized: "最大摄氧量", comment: "VO2 Max"), systemImage: "lungs.fill")
            }
        } header: {
            Text("心脏", comment: "Heart section header")
        }
    }

    private var bodySection: some View {
        Section {
            NavigationLink {
                BodyWeightDetailView()
            } label: {
                Label(String(localized: "体重", comment: "Body weight"), systemImage: "scalemass.fill")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .bodyFatPercentage)
            } label: {
                Label(String(localized: "体脂率", comment: "Body fat percentage"), systemImage: "percent")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .leanBodyMass)
            } label: {
                Label(String(localized: "去脂体重", comment: "Lean body mass"), systemImage: "scalemass")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .height)
            } label: {
                Label(String(localized: "身高", comment: "Height"), systemImage: "ruler")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .bodyMassIndex)
            } label: {
                Label(String(localized: "BMI", comment: "Body mass index"), systemImage: "number")
            }
        } header: {
            Text("身体测量", comment: "Body measurements section header")
        }
    }

    private var sleepSection: some View {
        Section {
            NavigationLink {
                SleepDetailView()
            } label: {
                Label(String(localized: "睡眠", comment: "Sleep"), systemImage: "bed.double.fill")
            }
        } header: {
            Text("睡眠", comment: "Sleep section header")
        }
    }

    private var nutritionSection: some View {
        Section {
            NavigationLink {
                GenericHealthDetailView(sampleType: .dietaryEnergyConsumed)
            } label: {
                Label(String(localized: "膳食能量摄入", comment: "Dietary energy"), systemImage: "fork.knife")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .dietaryProtein)
            } label: {
                Label(String(localized: "蛋白质", comment: "Protein"), systemImage: "fish.fill")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .dietaryCarbohydrates)
            } label: {
                Label(String(localized: "碳水化合物", comment: "Carbohydrates"), systemImage: "leaf.fill")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .dietaryFatTotal)
            } label: {
                Label(String(localized: "脂肪", comment: "Fat"), systemImage: "drop.fill")
            }
            NavigationLink {
                GenericHealthDetailView(sampleType: .dietaryWater)
            } label: {
                Label(String(localized: "饮水量", comment: "Water"), systemImage: "drop.dewy.fill")
            }
        } header: {
            Text("营养", comment: "Nutrition section header")
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
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(String(localized: "轻点查看详情", comment: "Card navigation a11y hint"))
    }
}

#Preview {
    DataView()
}
