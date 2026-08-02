// AI 标签根视图:存量硬编码中文文案(引导/隐私/a11y)预留待统一 i18n 迁移到
// Localizable.xcstrings,此处文件级静默,无语义改动。
// swiftlint:disable no_hardcoded_chinese
import AIService
import DesignKit
import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "AIView")

let aiPrivacyConsentKey = "ai_privacy_consent_accepted"

// MARK: - AIView

struct AIView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    #if os(iOS)
    @Environment(AppNavigation.self) private var navigation: AppNavigation?
    #endif
    @State private var viewModel = AIViewState()
    @State private var chatViewModel = AIChatViewModel()
    @State private var quickAnalysisCollapsed = false
    @AppStorage(aiPrivacyConsentKey) private var privacyConsented = false

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
            .onChange(of: privacyConsented) { _, newValue in
                viewModel.privacyAccepted = newValue
                if !newValue {
                    viewModel.cancelAllAnalysis()
                    chatViewModel.cancelStreaming()
                }
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
                    .foregroundStyle(theme.neutrals.text2)

                Text(String(localized: "需要配置 API Key", comment: "API key required title"))
                    .font(.title2.bold())
                    .foregroundStyle(theme.neutrals.text1)

                Text(String(localized: "AI 分析功能需要智谱 AI 的 API Key。请在设置中配置后再使用。", comment: "API key required description"))
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                #if os(iOS)
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
                #else
                Text(String(localized: "请在侧边栏「设置」中配置 API Key", comment: "macOS API key guide"))
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
                #endif

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
                    .foregroundStyle(theme.primary.primary)

                Text(String(localized: "隐私告知", comment: "Privacy notice title"))
                    .font(.title2.bold())
                    .foregroundStyle(theme.neutrals.text1)

                Card {
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
                        text: String(localized: "数据仅用于生成分析结果，具体数据处理方式以智谱 AI 服务条款为准。", comment: "Privacy purpose description")
                    )
                }

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
                .foregroundStyle(theme.primary.primary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(theme.neutrals.text1)
        }
    }

    // MARK: - Analysis Content

    private var analysisContent: some View {
        VStack(spacing: 0) {
            quickAnalysisHeader
            AIChatView(viewModel: chatViewModel)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !chatViewModel.messages.isEmpty {
                    Button {
                        chatViewModel.clearConversation()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(String(localized: "清空对话", comment: "Clear conversation a11y"))
                }
            }
        }
    }

    private var quickAnalysisHeader: some View {
        // Collapse control only meaningful once a conversation exists.
        let hasMessages = !chatViewModel.messages.isEmpty
        let effectivelyCollapsed = hasMessages && quickAnalysisCollapsed

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "ai_quick_analysis_section_title", comment: "Quick analysis section title above the chat"))
                    .font(TypeScale.title)
                    .foregroundStyle(theme.neutrals.text1)
                Spacer()
                if hasMessages {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            quickAnalysisCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: quickAnalysisCollapsed ? "chevron.down" : "chevron.up")
                            .foregroundStyle(theme.neutrals.text2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(quickAnalysisCollapsed
                        ? String(localized: "ai_quick_analysis_expand", comment: "Expand quick analysis header a11y")
                        : String(localized: "ai_quick_analysis_collapse", comment: "Collapse quick analysis header a11y"))
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, effectivelyCollapsed ? 8 : 12)

            if !effectivelyCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
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
                            .frame(width: 280)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
                Divider()
            }
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
    private var analysisTasks: [QuickAnalysisType: Task<Void, Never>] = [:]

    func checkAPIKey() {
        do {
            let key = try keychainHelper.load(service: apiKeyService)
            hasAPIKey = !key.isEmpty
        } catch {
            hasAPIKey = false
        }
    }

    func loadPrivacyConsent() {
        privacyAccepted = UserDefaults.standard.bool(forKey: aiPrivacyConsentKey)
    }

    func acceptPrivacyConsent() {
        UserDefaults.standard.set(true, forKey: aiPrivacyConsentKey)
        privacyAccepted = true
    }

    func revokePrivacyConsent() {
        UserDefaults.standard.set(false, forKey: aiPrivacyConsentKey)
        privacyAccepted = false
    }

    func cancelAllAnalysis() {
        for (type, task) in analysisTasks {
            task.cancel()
            if case .loading = cardStates[type] {
                cardStates[type] = .idle
            }
        }
        analysisTasks.removeAll()
    }

    func runAnalysis(type: QuickAnalysisType, modelContext: ModelContext) async {
        if case .loading = cardStates[type] { return }

        analysisTasks[type]?.cancel()
        let task = Task {
            await performAnalysis(type: type, modelContext: modelContext)
        }
        analysisTasks[type] = task
        await task.value
    }

    private func performAnalysis(type: QuickAnalysisType, modelContext: ModelContext) async {
        cardStates[type] = .loading
        logger.info("analysis started type=\(type.rawValue)")
        let start = ContinuousClock.now

        do {
            let apiKey = try keychainHelper.load(service: apiKeyService)
            let router = AIRouter.makeDefault(zhipuAPIKey: apiKey)
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

            let selectedModel = UserDefaults.standard.string(forKey: "aiModel") ?? AIModel.glm4Flash.rawValue
            let response = try await router.execute(kind: .chat, messages: chatMessages, model: selectedModel)

            guard !Task.isCancelled else {
                cardStates[type] = .idle
                return
            }

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info("analysis completed type=\(type.rawValue) ms=\(ms)")

            cardStates[type] = .result(response.content)
        } catch {
            guard !Task.isCancelled else {
                cardStates[type] = .idle
                return
            }
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
        .designThemePreview()
}
