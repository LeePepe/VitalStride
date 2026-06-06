import AIService
import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "AIView")

private let privacyConsentKey = "ai_privacy_consent_accepted"

// MARK: - AIView

struct AIView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    @State private var viewModel = AIViewState()

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.hasAPIKey {
                    apiKeyGuideView
                } else if !viewModel.privacyAccepted {
                    privacyConsentView
                } else {
                    analysisContent
                }
            }
            .navigationTitle("AI")
            .task {
                viewModel.checkAPIKey()
                viewModel.loadPrivacyConsent()
            }
        }
    }

    // MARK: - API Key Guide

    private var apiKeyGuideView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text(String(localized: "需要配置 API Key", comment: "API key required title"))
                    .font(.title2.bold())

                Text(String(localized: "AI 分析功能需要智谱 AI 的 API Key。请在设置中配置后再使用。", comment: "API key required description"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    navigation?.selectedTab = .settings
                } label: {
                    Label(
                        String(localized: "前往「设置」配置 API Key", comment: "Navigate to settings for API key"),
                        systemImage: "gearshape"
                    )
                    .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(String(localized: "切换到设置页面配置 API Key", comment: "API key settings a11y hint"))

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    // MARK: - Privacy Consent

    private var privacyConsentView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 40)

                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                Text(String(localized: "隐私告知", comment: "Privacy notice title"))
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    privacyBullet(
                        icon: "arrow.up.doc",
                        text: String(localized: "AI 分析会将你的训练数据（训练记录、组数、重量）和健康数据（心率、睡眠、步数）发送到第三方服务器进行分析。", comment: "Privacy data sent description")
                    )
                    privacyBullet(
                        icon: "building.2",
                        text: String(localized: "数据将发送至智谱 AI（BigModel）服务器。", comment: "Privacy provider description")
                    )
                    privacyBullet(
                        icon: "checkmark.shield",
                        text: String(localized: "数据仅用于生成分析结果，不会被永久存储。", comment: "Privacy purpose description")
                    )
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    viewModel.acceptPrivacyConsent()
                } label: {
                    Text(String(localized: "我已了解，开始使用", comment: "Accept privacy consent button"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(String(localized: "确认隐私告知并开始使用 AI 功能", comment: "Accept privacy a11y hint"))

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    private func privacyBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Analysis Content

    private var analysisContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                quickAnalysisSection
                conversationPlaceholder
            }
            .padding()
        }
    }

    private var quickAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "快捷分析", comment: "Quick analysis section title"))
                .font(.headline)

            ForEach(QuickAnalysisType.allCases) { type in
                AIQuickAnalysisCard(
                    analysisType: type,
                    state: viewModel.cardStates[type, default: .idle],
                    onTap: {
                        Task {
                            await viewModel.runAnalysis(
                                type: type,
                                modelContext: modelContext
                            )
                        }
                    },
                    onRetry: {
                        Task {
                            await viewModel.runAnalysis(
                                type: type,
                                modelContext: modelContext
                            )
                        }
                    }
                )
            }
        }
    }

    private var conversationPlaceholder: some View {
        VStack(spacing: 8) {
            Divider()
                .padding(.vertical, 8)

            Text(String(localized: "对话功能即将推出", comment: "Conversation placeholder"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - View State

@Observable
@MainActor
final class AIViewState {
    var hasAPIKey = false
    var privacyAccepted = false
    var cardStates: [QuickAnalysisType: QuickAnalysisState] = [:]

    private let keychainHelper = KeychainHelper()
    private let apiKeyService = AISettingsSection.apiKeyKeychainService

    func checkAPIKey() {
        do {
            let key = try keychainHelper.load(service: apiKeyService)
            hasAPIKey = !key.isEmpty
        } catch {
            hasAPIKey = false
        }
    }

    func loadPrivacyConsent() {
        privacyAccepted = UserDefaults.standard.bool(forKey: privacyConsentKey)
    }

    func acceptPrivacyConsent() {
        UserDefaults.standard.set(true, forKey: privacyConsentKey)
        privacyAccepted = true
    }

    func runAnalysis(type: QuickAnalysisType, modelContext: ModelContext) async {
        if case .loading = cardStates[type] { return }

        cardStates[type] = .loading
        logger.info("analysis started type=\(type.rawValue)")
        let start = ContinuousClock.now

        do {
            let apiKey = try keychainHelper.load(service: apiKeyService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let healthService = HealthKitService(deviceIdentifier: "ios-ai")

            let context = await AIPromptBuilder.buildContext(
                modelContext: modelContext,
                healthKitService: healthService,
                dateRange: type.dateRange
            )

            let promptMessages = type.buildPrompt(context: context)
            let chatMessages = promptMessages.map {
                ChatMessage(role: $0.role, content: $0.content)
            }

            let response = try await provider.chat(messages: chatMessages, model: nil)

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("analysis completed type=\(type.rawValue) ms=\(ms)")

            cardStates[type] = .result(response.content)
        } catch {
            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.error("analysis failed type=\(type.rawValue) ms=\(ms) error=\(error.localizedDescription)")

            cardStates[type] = .error(error.localizedDescription)
        }
    }
}

// MARK: - Previews

#Preview("With Content") {
    AIView()
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}
