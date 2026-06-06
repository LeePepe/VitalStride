import AIService
import HealthKitService
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "AIQuickAnalysis")

enum QuickAnalysisType: String, CaseIterable, Identifiable, Sendable {
    case weeklySummary = "weekly_summary"
    case recovery = "recovery"
    case prDetection = "pr_detection"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weeklySummary: String(localized: "本周训练总结", comment: "Weekly workout summary card title")
        case .recovery: String(localized: "恢复建议", comment: "Recovery advice card title")
        case .prDetection: String(localized: "个人记录", comment: "Personal record card title")
        }
    }

    var subtitle: String {
        switch self {
        case .weeklySummary: String(localized: "分析本周训练量与频率", comment: "Weekly summary card subtitle")
        case .recovery: String(localized: "评估恢复状态与建议", comment: "Recovery card subtitle")
        case .prDetection: String(localized: "检测历史最佳成绩", comment: "PR detection card subtitle")
        }
    }

    var iconName: String {
        switch self {
        case .weeklySummary: "chart.bar.xaxis.ascending"
        case .recovery: "heart.circle"
        case .prDetection: "trophy"
        }
    }

    var iconColor: Color {
        switch self {
        case .weeklySummary: .blue
        case .recovery: .green
        case .prDetection: .orange
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .weeklySummary: String(localized: "本周训练总结，点击生成 AI 分析", comment: "Weekly summary a11y label")
        case .recovery: String(localized: "恢复建议，点击生成 AI 分析", comment: "Recovery a11y label")
        case .prDetection: String(localized: "个人记录，点击检测历史最佳", comment: "PR detection a11y label")
        }
    }

    var dateRange: DateInterval {
        let calendar = Calendar.current
        let now = Date()
        switch self {
        case .weeklySummary:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return DateInterval(start: startOfWeek, end: now)
        case .recovery:
            let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now))!
            return DateInterval(start: twoWeeksAgo, end: now)
        case .prDetection:
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: calendar.startOfDay(for: now))!
            return DateInterval(start: sixMonthsAgo, end: now)
        }
    }

    func buildPrompt(context: AIPromptContext) -> [ChatMessagePayload] {
        switch self {
        case .weeklySummary: AIPromptBuilder.buildWeeklySummaryPrompt(context: context)
        case .recovery: AIPromptBuilder.buildRecoveryPrompt(context: context)
        case .prDetection: AIPromptBuilder.buildPRDetectionPrompt(context: context)
        }
    }
}

// MARK: - Card State

enum QuickAnalysisState: Sendable {
    case idle
    case loading
    case result(String)
    case error(String)
}

// MARK: - Card View

struct AIQuickAnalysisCard: View {
    let analysisType: QuickAnalysisType
    let state: QuickAnalysisState
    let onTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader

            switch state {
            case .idle:
                idleContent
            case .loading:
                loadingContent
            case let .result(text):
                resultContent(text: text)
            case let .error(message):
                errorContent(message: message)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(analysisType.accessibilityLabel)
    }

    private var cardHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: analysisType.iconName)
                .font(.title2)
                .foregroundStyle(analysisType.iconColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(analysisType.title)
                    .font(.headline)
                Text(analysisType.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if case .loading = state {
                ProgressView()
                    .accessibilityLabel(String(localized: "正在分析", comment: "Loading a11y label"))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private var idleContent: some View {
        Button(action: onTap) {
            HStack {
                Text(String(localized: "开始分析", comment: "Start analysis button"))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "sparkles")
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(analysisType.iconColor)
        .accessibilityHint(String(localized: "点击开始 AI 分析", comment: "Start analysis a11y hint"))
    }

    private var loadingContent: some View {
        Text(String(localized: "正在组装数据并分析…", comment: "Loading analysis text"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func resultContent(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.subheadline)
                .textSelection(.enabled)
                .accessibilityLabel(text)

            Button(action: onTap) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                    Text(String(localized: "重新分析", comment: "Re-analyze button"))
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func errorContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)

            Button(action: onRetry) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                    Text(String(localized: "重试", comment: "Retry button"))
                        .font(.caption.weight(.medium))
                }
            }
            .accessibilityLabel(String(localized: "重试 AI 分析", comment: "Retry a11y label"))
        }
    }
}

#Preview("Idle") {
    AIQuickAnalysisCard(
        analysisType: .weeklySummary,
        state: .idle,
        onTap: {},
        onRetry: {}
    )
    .padding()
}

#Preview("Loading") {
    AIQuickAnalysisCard(
        analysisType: .recovery,
        state: .loading,
        onTap: {},
        onRetry: {}
    )
    .padding()
}

#Preview("Result") {
    AIQuickAnalysisCard(
        analysisType: .prDetection,
        state: .result("你在卧推上达到了新的个人记录！80kg × 5 是一个很好的突破。建议继续保持当前的渐进超负荷策略。"),
        onTap: {},
        onRetry: {}
    )
    .padding()
}

#Preview("Error") {
    AIQuickAnalysisCard(
        analysisType: .weeklySummary,
        state: .error("网络请求失败，请检查网络连接。"),
        onTap: {},
        onRetry: {}
    )
    .padding()
}
