import AIService
import OSLog
import SwiftUI

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
    static let apiKeyKeychainService = "\(KeychainHelper.defaultServicePrefix).apikey"

    @AppStorage("aiModel") private var selectedModel: AIModel = .glm4Flash
    @State private var hasAPIKey = false
    @State private var apiKeyInput = ""
    @State private var showClearConfirmation = false

    private let keychainHelper = KeychainHelper()

    var body: some View {
        Section {
            providerRow
            apiKeyRow
            modelPicker
        } header: {
            Text("AI 服务")
        } footer: {
            Text("前往 [open.bigmodel.cn](https://open.bigmodel.cn) 获取 API Key")
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
            Text("确定要清除已保存的 API Key 吗？")
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
        }
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
