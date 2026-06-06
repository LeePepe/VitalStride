import AIService
import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import os

#if canImport(UIKit)
import UIKit
#endif

private let logger = Logger(subsystem: "com.vitalstride", category: "AIChat")

// MARK: - Chat Message Model

struct AIChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: AIChatRole
    let content: String
    let timestamp: Date
    let state: AIChatMessageState

    init(
        id: UUID = UUID(),
        role: AIChatRole,
        content: String,
        timestamp: Date = Date(),
        state: AIChatMessageState = .complete
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.state = state
    }

    func appendingContent(_ extra: String, state newState: AIChatMessageState) -> AIChatMessage {
        AIChatMessage(id: id, role: role, content: content + extra, timestamp: timestamp, state: newState)
    }

    func withState(_ newState: AIChatMessageState) -> AIChatMessage {
        AIChatMessage(id: id, role: role, content: content, timestamp: timestamp, state: newState)
    }
}

enum AIChatRole: Sendable {
    case user
    case assistant
}

enum AIChatMessageState: Sendable, Equatable {
    case complete
    case streaming
    case error(String)
}

// MARK: - View Model

@Observable
@MainActor
final class AIChatViewModel {
    private(set) var messages: [AIChatMessage] = []
    var inputText = ""
    private(set) var isStreaming = false
    private(set) var lastCompletedMessageId: UUID?

    private var streamingTask: Task<Void, Never>?
    private let keychainHelper = KeychainHelper()
    private let apiKeyService = AISettingsSection.apiKeyKeychainService

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    func sendMessage(modelContext: ModelContext) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        inputText = ""
        logger.info("chat_message_sent")

        messages.append(AIChatMessage(role: .user, content: text))
        startStreaming(modelContext: modelContext)
    }

    func retryLastMessage(modelContext: ModelContext) {
        guard !isStreaming else { return }
        if let last = messages.last, last.role == .assistant, case .error = last.state {
            messages.removeLast()
        }
        logger.info("chat_retry")
        startStreaming(modelContext: modelContext)
    }

    func clearConversation() {
        streamingTask?.cancel()
        streamingTask = nil
        isStreaming = false
        messages = []
        lastCompletedMessageId = nil
        logger.info("chat_cleared")
    }

    private func startStreaming(modelContext: ModelContext) {
        streamingTask?.cancel()
        streamingTask = Task { [weak self] in
            await self?.performStreaming(modelContext: modelContext)
        }
    }

    private func performStreaming(modelContext: ModelContext) async {
        isStreaming = true
        let start = ContinuousClock.now
        var chunksReceived = 0

        let assistantId = UUID()
        messages.append(AIChatMessage(id: assistantId, role: .assistant, content: "", state: .streaming))

        do {
            let apiKey = try keychainHelper.load(service: apiKeyService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let healthService = HealthKitService(deviceIdentifier: "ios-ai")

            let dateRange = DateInterval(
                start: Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
                end: Date()
            )
            let context = await AIPromptBuilder.buildContext(
                modelContext: modelContext,
                healthKitService: healthService,
                dateRange: dateRange
            )
            let systemPrompt = AIPromptBuilder.buildSystemContext(context: context)

            var apiMessages = [ChatMessage(role: "system", content: systemPrompt)]
            for msg in messages where msg.id != assistantId {
                apiMessages.append(ChatMessage(
                    role: msg.role == .user ? "user" : "assistant",
                    content: msg.content
                ))
            }

            let selectedModel = UserDefaults.standard.string(forKey: "aiModel")
                ?? AIModel.glm4Flash.rawValue
            let stream = provider.chatStream(messages: apiMessages, model: selectedModel)

            var contentBuffer = ""
            var lastUIUpdate = ContinuousClock.now
            let uiUpdateInterval: Duration = .milliseconds(50)

            for try await chunk in stream {
                guard !Task.isCancelled else { break }
                chunksReceived += 1
                contentBuffer += chunk.content

                let now = ContinuousClock.now
                if chunk.isFinished || now - lastUIUpdate >= uiUpdateInterval {
                    updateMessage(id: assistantId) {
                        AIChatMessage(
                            id: $0.id, role: $0.role, content: contentBuffer,
                            timestamp: $0.timestamp,
                            state: chunk.isFinished ? .complete : .streaming
                        )
                    }
                    lastUIUpdate = now
                }
            }

            if Task.isCancelled {
                updateMessage(id: assistantId) {
                    AIChatMessage(
                        id: $0.id, role: $0.role, content: contentBuffer,
                        timestamp: $0.timestamp, state: .complete
                    )
                }
                let ms = elapsedMs(since: start)
                logger.info("streaming_cancelled chunks=\(chunksReceived) ms=\(ms)")
            } else {
                updateMessage(id: assistantId) {
                    AIChatMessage(
                        id: $0.id, role: $0.role, content: contentBuffer,
                        timestamp: $0.timestamp, state: .complete
                    )
                }
                lastCompletedMessageId = assistantId
                let ms = elapsedMs(since: start)
                logger.info("streaming_completed chunks=\(chunksReceived) ms=\(ms)")
            }
        } catch {
            let ms = elapsedMs(since: start)
            logger.error("streaming_failed chunks=\(chunksReceived) ms=\(ms) error=\(error.localizedDescription)")
            updateMessage(id: assistantId) { $0.withState(.error(error.localizedDescription)) }
        }

        isStreaming = false
    }

    private func updateMessage(id: UUID, transform: (AIChatMessage) -> AIChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = transform(messages[index])
    }

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int64 {
        let elapsed = ContinuousClock.now - start
        return elapsed.components.seconds * 1000
            + elapsed.components.attoseconds / 1_000_000_000_000_000
    }
}

// MARK: - Chat View

struct AIChatView<EmptyContent: View>: View {
    @Bindable var viewModel: AIChatViewModel
    @Environment(\.modelContext) private var modelContext
    let emptyContent: EmptyContent

    init(viewModel: AIChatViewModel, @ViewBuilder emptyContent: () -> EmptyContent) {
        self.viewModel = viewModel
        self.emptyContent = emptyContent()
    }

    var body: some View {
        VStack(spacing: 0) {
            messageArea
            Divider()
            inputBar
        }
        #if canImport(UIKit)
        .onChange(of: viewModel.lastCompletedMessageId) { _, newId in
            guard newId != nil else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: String(localized: "AI 回复完成", comment: "AI reply a11y announcement")
            )
        }
        #endif
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        emptyContent
                        chatEmptyPrompt
                    }

                    ForEach(viewModel.messages) { message in
                        AIChatMessageBubble(message: message) {
                            viewModel.retryLastMessage(modelContext: modelContext)
                        }
                        .id(message.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToLast(proxy: proxy)
            }
            .onChange(of: viewModel.lastCompletedMessageId) { _, _ in
                scrollToLast(proxy: proxy)
            }
        }
    }

    private var chatEmptyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text(String(
                localized: "向 AI 助手提问关于训练和健康的问题",
                comment: "Chat empty state prompt"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(
                String(localized: "输入你的问题...", comment: "Chat input placeholder"),
                text: $viewModel.inputText,
                axis: .vertical
            )
            .lineLimit(1...5)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel(String(localized: "向 AI 提问", comment: "Chat input a11y label"))

            Button {
                viewModel.sendMessage(modelContext: modelContext)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel(String(localized: "发送消息", comment: "Send button a11y"))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func scrollToLast(proxy: ScrollViewProxy) {
        guard let lastId = viewModel.messages.last?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(lastId, anchor: .bottom)
        }
    }
}

extension AIChatView where EmptyContent == EmptyView {
    init(viewModel: AIChatViewModel) {
        self.viewModel = viewModel
        self.emptyContent = EmptyView()
    }
}

// MARK: - Message Bubble

struct AIChatMessageBubble: View {
    let message: AIChatMessage
    let onRetry: () -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if case .streaming = message.state, message.content.isEmpty {
                    AIChatTypingIndicator()
                }

                if !message.content.isEmpty {
                    bubbleContent
                }

                if case let .error(errorMessage) = message.state {
                    errorView(errorMessage)
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if message.role == .user {
            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
                .textSelection(.enabled)
        } else {
            Text(message.content)
                .font(.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .textSelection(.enabled)
        }
    }

    private func errorView(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)

            Button(action: onRetry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                    Text(String(localized: "重试", comment: "Retry button"))
                        .font(.caption.weight(.medium))
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel(String(localized: "重试发送消息", comment: "Retry a11y label"))
        }
    }

    private var accessibilityText: String {
        let sender = message.role == .user
            ? String(localized: "你", comment: "User sender a11y")
            : String(localized: "AI", comment: "AI sender a11y")

        if case .streaming = message.state, message.content.isEmpty {
            return String(localized: "AI 正在回复", comment: "AI typing a11y")
        }
        if case let .error(msg) = message.state {
            return "\(sender): \(msg)"
        }
        return "\(sender): \(message.content)"
    }
}

// MARK: - Typing Indicator

struct AIChatTypingIndicator: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate * 2.5) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(index == phase ? 1.0 : 0.3)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel(String(localized: "AI 正在回复", comment: "Typing indicator a11y"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Previews

#Preview("Empty State") {
    NavigationStack {
        AIChatView(viewModel: AIChatViewModel()) {
            Text("Quick Analysis Cards Here")
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .navigationTitle("AI")
    }
    .modelContainer(try! ModelContainerConfiguration.makeTestContainer())
}

#Preview("Typing Indicator") {
    AIChatTypingIndicator()
        .padding()
}
