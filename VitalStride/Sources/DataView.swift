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
            let revoked = (status == .shouldRequest)
            if revoked, !needsAuthorization {
                await healthDataCache.invalidateAll()
            }
            needsAuthorization = revoked
        } catch {
            if !needsAuthorization {
                await healthDataCache.invalidateAll()
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
