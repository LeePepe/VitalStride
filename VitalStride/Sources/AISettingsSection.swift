import AIService
import OSLog
import SwiftUI
import TelemetryKit

private let logger = Logger(subsystem: "com.vitalstride", category: "AISettings")

enum AIModel: String, CaseIterable, Sendable {
    case glm4Flash = "glm-4-flash"
    case glm4Plus = "glm-4-plus"

    var displayName: String {
        switch self {
        case .glm4Flash: "GLM-4-Flash (\(String(localized: "免费", comment: "Free tier label")))"
        case .glm4Plus: "GLM-4-Plus (\(String(localized: "付费", comment: "Paid tier label")))"
        }
    }
}

struct AISettingsSection: View {
    nonisolated static let apiKeyKeychainService = "\(KeychainHelper.defaultServicePrefix).apikey"

    @AppStorage("aiModel") private var selectedModel: AIModel = .glm4Flash
    @AppStorage(aiPrivacyConsentKey) private var privacyConsented = false
    @State private var hasAPIKey = false
    @State private var apiKeyInput = ""
    @State private var showClearConfirmation = false
    @State private var showRevokeConsentConfirmation = false

    private let keychainHelper = KeychainHelper()

    var body: some View {
        Section {
            providerRow
            apiKeyRow
            modelPicker
            if privacyConsented {
                privacyConsentRow
            }
        } header: {
            Text(String(localized: "AI 服务", comment: "AI settings section header"))
        } footer: {
            Text(String(localized: "前往 [open.bigmodel.cn](https://open.bigmodel.cn) 获取 API Key", comment: "AI settings section footer"))
        }
        .onAppear(perform: loadAPIKeyState)
        .onDisappear(perform: savePendingAPIKey)
        .alert(
            String(localized: "确认清除", comment: "Clear API key confirmation title"),
            isPresented: $showClearConfirmation
        ) {
            Button(String(localized: "取消", comment: "Cancel button"), role: .cancel) {}
            Button(String(localized: "清除", comment: "Clear button"), role: .destructive, action: clearAPIKey)
        } message: {
            Text(String(localized: "确定要清除已保存的 API Key 吗？", comment: "Clear API key confirmation message"))
        }
        .alert(
            String(localized: "撤回数据使用许可", comment: "Revoke consent title"),
            isPresented: $showRevokeConsentConfirmation
        ) {
            Button(String(localized: "取消", comment: "Cancel button"), role: .cancel) {}
            Button(String(localized: "撤回", comment: "Revoke button"), role: .destructive) {
                privacyConsented = false
            }
        } message: {
            Text(String(localized: "撤回后需重新确认隐私告知才能使用 AI 分析功能。", comment: "Revoke consent message"))
        }
    }

    private var providerRow: some View {
        HStack {
            Label(String(localized: "服务商", comment: "AI provider label"), systemImage: "brain")
            Spacer()
            Text("智谱 AI")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var apiKeyRow: some View {
        if hasAPIKey {
            HStack {
                Label("API Key", systemImage: "key")
                Spacer()
                Text("••••••••")
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showClearConfirmation = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "清除 API Key", comment: "Clear API key button a11y"))
            }
        } else {
            SecureField(
                String(localized: "输入 API Key", comment: "API key placeholder"),
                text: $apiKeyInput
            )
            .onSubmit(saveAPIKey)
            .accessibilityLabel(String(localized: "AI API Key 输入框", comment: "API key input a11y"))
        }
    }

    private var modelPicker: some View {
        Picker(selection: $selectedModel) {
            ForEach(AIModel.allCases, id: \.self) { model in
                Text(model.displayName).tag(model)
            }
        } label: {
            Label(String(localized: "模型", comment: "AI model label"), systemImage: "cpu")
        }
        .accessibilityLabel(String(localized: "AI 模型选择", comment: "AI model picker a11y"))
        .onChange(of: selectedModel) { oldValue, newValue in
            logger.info("AI model changed: from=\(oldValue.rawValue) to=\(newValue.rawValue)")
            if let identifier = TelemetryIdentifier(validating: newValue.rawValue) {
                TelemetryService.shared.trackNonisolated(.aiModelChanged(model: identifier))
            }
        }
    }

    private var privacyConsentRow: some View {
        Button(role: .destructive) {
            showRevokeConsentConfirmation = true
        } label: {
            Label(
                String(localized: "撤回数据使用许可", comment: "Revoke privacy consent label"),
                systemImage: "hand.raised"
            )
        }
        .accessibilityLabel(String(localized: "撤回 AI 数据使用许可", comment: "Revoke consent a11y"))
    }

    private func loadAPIKeyState() {
        do {
            _ = try keychainHelper.load(service: Self.apiKeyKeychainService)
            hasAPIKey = true
        } catch {
            hasAPIKey = false
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try keychainHelper.save(key: trimmed, service: Self.apiKeyKeychainService)
            hasAPIKey = true
            apiKeyInput = ""
            logger.info("AI API key configured")
        } catch {
            logger.error("Failed to save API key: \(error.localizedDescription)")
        }
    }

    private func clearAPIKey() {
        do {
            try keychainHelper.delete(service: Self.apiKeyKeychainService)
            hasAPIKey = false
            logger.info("AI API key cleared")
        } catch {
            logger.error("Failed to clear API key: \(error.localizedDescription)")
        }
    }

    private func savePendingAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saveAPIKey()
    }
}

#Preview("AI 设置") {
    Form {
        AISettingsSection()
    }
}
