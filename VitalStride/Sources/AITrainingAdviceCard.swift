// AI 训练建议卡片:存量硬编码中文文案(标题/标签/肌群名/a11y)预留待统一 i18n
// 迁移到 Localizable.xcstrings,此处文件级静默,无语义改动。
// swiftlint:disable no_hardcoded_chinese
import AIService
import DesignKit
import SwiftData
import SwiftUI
import VitalModels
import os

private let logger = Logger(subsystem: "com.vitalstride", category: "AITrainingAdvice")
private let signposter = OSSignposter(subsystem: "com.vitalstride", category: "AITrainingAdvice")

// MARK: - Card State

enum TrainingAdviceState: Sendable {
    case idle
    case loading
    case loaded(TrainingRecommendation, source: TrainingAdviceSource)
    case error(String)
}

enum TrainingAdviceSource: Sendable {
    case fresh
    case cache(generatedAt: Date)
}

// MARK: - Card View

struct AITrainingAdviceCard: View {
    @Environment(\.theme) private var theme
    let state: TrainingAdviceState
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        Card {
            cardHeader

            switch state {
            case .idle:
                EmptyView()
            case .loading:
                loadingContent
            case let .loaded(recommendation, source):
                loadedContent(recommendation: recommendation, source: source)
            case let .error(message):
                errorContent(message: message)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Header

    private var cardHeader: some View {
        Button(action: {
            onToggleExpand()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.primary.primary)
                    .frame(width: 32, height: 32)
                    .background(theme.primary.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "今日训练建议", comment: "Training advice card title"))
                        .font(TypeScale.title)
                        .foregroundStyle(theme.neutrals.text1)

                    summaryText
                        .font(TypeScale.meta)
                        .foregroundStyle(theme.neutrals.text2)
                }

                Spacer()

                if case .loading = state {
                    ProgressView()
                        .accessibilityLabel(
                            String(localized: "正在生成建议", comment: "Loading advice a11y label")
                        )
                        .accessibilityValue(
                            String(localized: "正在生成建议", comment: "Loading advice a11y value")
                        )
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(theme.neutrals.text2)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(
            isExpanded
                ? String(localized: "轻点两下以折叠", comment: "Collapse advice a11y hint")
                : String(localized: "轻点两下以展开", comment: "Expand advice a11y hint")
        )
    }

    @ViewBuilder
    private var summaryText: some View {
        switch state {
        case .idle:
            Text(String(localized: "点击展开查看 AI 训练建议", comment: "Idle advice summary"))
        case .loading:
            Text(String(localized: "正在分析训练历史…", comment: "Loading advice summary"))
        case let .loaded(recommendation, _):
            Text(recommendation.title)
        case .error:
            Text(String(localized: "建议生成失败", comment: "Error advice summary"))
        }
    }

    // MARK: - Loading

    private var loadingContent: some View {
        Text(String(localized: "正在根据你的训练历史生成个性化建议…", comment: "Loading advice detail"))
            .font(TypeScale.body)
            .foregroundStyle(theme.neutrals.text2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: - Loaded

    @ViewBuilder
    private func loadedContent(
        recommendation: TrainingRecommendation,
        source: TrainingAdviceSource
    ) -> some View {
        if isExpanded {
            expandedContent(recommendation: recommendation, source: source)
        }
    }

    private func expandedContent(
        recommendation: TrainingRecommendation,
        source: TrainingAdviceSource
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !recommendation.muscleGroups.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "推荐肌群", comment: "Recommended muscle groups label"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.neutrals.text2)
                    let displayGroups = recommendation.muscleGroups.map { localizedMuscleGroup($0) }
                    Text(displayGroups.joined(separator: "、"))
                        .font(TypeScale.body)
                        .foregroundStyle(theme.neutrals.text1)
                        .accessibilityLabel(
                            String(
                                localized: "推荐肌群：\(displayGroups.joined(separator: "、"))",
                                comment: "Muscle groups a11y label"
                            )
                        )
                }
            }

            if !recommendation.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "推荐动作", comment: "Recommended exercises label"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.neutrals.text2)
                    Text(recommendation.exercises.joined(separator: "、"))
                        .font(TypeScale.body)
                        .foregroundStyle(theme.neutrals.text1)
                        .accessibilityLabel(
                            String(
                                localized: "推荐动作：\(recommendation.exercises.joined(separator: "、"))",
                                comment: "Exercises a11y label"
                            )
                        )
                }
            }

            if !recommendation.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "推荐理由", comment: "Reasoning label"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.neutrals.text2)
                    Text(recommendation.reasoning)
                        .font(TypeScale.body)
                        .foregroundStyle(theme.neutrals.text1)
                        .accessibilityLabel(
                            String(
                                localized: "推荐理由：\(recommendation.reasoning)",
                                comment: "Reasoning a11y label"
                            )
                        )
                }
            }

            HStack {
                if case let .cache(generatedAt) = source {
                    Text(
                        String(
                            localized: "更新于 \(generatedAt, format: .relative(presentation: .named))",
                            comment: "Cache update time"
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(theme.neutrals.text3)
                }

                Spacer()

                Button(action: onRefresh) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text(String(localized: "刷新", comment: "Refresh advice button"))
                            .font(.caption)
                    }
                    .frame(minHeight: 44)
                }
                .foregroundStyle(theme.neutrals.text2)
                .accessibilityLabel(
                    String(localized: "刷新训练建议", comment: "Refresh advice a11y label")
                )
            }
        }
    }

    // MARK: - Error

    private func errorContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(theme.danger)

            Button(action: onRefresh) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                    Text(String(localized: "重试", comment: "Retry button"))
                        .font(.caption.weight(.medium))
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel(
                String(localized: "重试生成训练建议", comment: "Retry advice a11y label")
            )
        }
    }

    // MARK: - Helpers

    private func localizedMuscleGroup(_ key: String) -> String {
        switch key {
        case "chest": String(localized: "胸", comment: "Chest muscle group")
        case "back": String(localized: "背", comment: "Back muscle group")
        case "shoulders": String(localized: "肩", comment: "Shoulders muscle group")
        case "legs": String(localized: "腿", comment: "Legs muscle group")
        case "arms": String(localized: "臂", comment: "Arms muscle group")
        case "core": String(localized: "核心", comment: "Core muscle group")
        case "fullBody": String(localized: "全身", comment: "Full body muscle group")
        default: key
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class TrainingAdviceViewModel {
    var state: TrainingAdviceState = .idle
    var isExpanded = false

    private var loadTask: Task<Void, Never>?
    private let keychainHelper = KeychainHelper()
    private let apiKeyService = AISettingsSection.apiKeyKeychainService

    func loadAdviceIfNeeded(modelContext: ModelContext) {
        guard case .idle = state else { return }
        loadAdvice(modelContext: modelContext, forceRefresh: false)
    }

    func refresh(modelContext: ModelContext) {
        signposter.emitEvent("ai_training_advice_refresh")
        logger.info("event=ai_training_advice_refresh")
        loadAdvice(modelContext: modelContext, forceRefresh: true)
    }

    func toggleExpand() {
        isExpanded.toggle()
        if isExpanded {
            signposter.emitEvent("ai_training_advice_expand")
            logger.info("event=ai_training_advice_expand")
        } else {
            signposter.emitEvent("ai_training_advice_collapse")
            logger.info("event=ai_training_advice_collapse")
        }
    }

    private func loadAdvice(modelContext: ModelContext, forceRefresh: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            await performLoad(modelContext: modelContext, forceRefresh: forceRefresh)
        }
    }

    private func performLoad(modelContext: ModelContext, forceRefresh: Bool) async {
        state = .loading
        let start = ContinuousClock.now

        do {
            let apiKey = try keychainHelper.load(service: apiKeyService)
            let provider = ZhipuProvider(apiKey: apiKey)
            let container = modelContext.container

            let trainingContext = buildTrainingContext(modelContext: modelContext)

            let service = AIAnalysisService(
                modelContainer: container,
                provider: provider
            )

            let recommendation = try await service.generateTrainingAdvice(
                context: trainingContext,
                forceRefresh: forceRefresh
            )

            guard !Task.isCancelled else {
                state = .idle
                return
            }

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info(
                "event=ai_training_advice_request_duration_ms duration_ms=\(ms) success=true"
            )

            let source = detectSource(modelContext: modelContext)
            state = .loaded(recommendation, source: source)

            let sourceLabel = switch source {
            case .fresh: "fresh"
            case .cache: "cache"
            }
            signposter.emitEvent("ai_training_advice_shown", "\(sourceLabel)")
            logger.info("event=ai_training_advice_shown source=\(sourceLabel)")

        } catch {
            guard !Task.isCancelled else {
                state = .idle
                return
            }

            let elapsed = ContinuousClock.now - start
            let ms = elapsed.components.seconds * 1000
                + elapsed.components.attoseconds / 1_000_000_000_000_000
            logger.info(
                "event=ai_training_advice_request_duration_ms duration_ms=\(ms) success=false"
            )

            signposter.emitEvent("ai_training_advice_degraded")
            logger.info("event=ai_training_advice_degraded error=\(error.localizedDescription)")
            state = .error(
                String(localized: "暂时无法生成训练建议，请稍后重试。", comment: "Advice error message")
            )
        }
    }

    private func detectSource(modelContext: ModelContext) -> TrainingAdviceSource {
        let descriptor = FetchDescriptor<TrainingAdviceCache>()
        if let cached = try? modelContext.fetch(descriptor).first {
            if cached.isExpired {
                return .cache(generatedAt: cached.generatedAt)
            }
            let age = Date().timeIntervalSince(cached.generatedAt)
            if age > 5 {
                return .cache(generatedAt: cached.generatedAt)
            }
        }
        return .fresh
    }
}

// MARK: - TrainingContext Builder

@MainActor
func buildTrainingContext(modelContext: ModelContext) -> TrainingContext {
    let now = Date()
    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now)!

    var descriptor = FetchDescriptor<Workout>(
        predicate: #Predicate<Workout> { workout in
            workout.startDate >= thirtyDaysAgo && workout.endDate != nil
        },
        sortBy: [SortDescriptor(\.startDate, order: .reverse)]
    )
    descriptor.fetchLimit = 10

    let workouts: [Workout]
    do {
        workouts = try modelContext.fetch(descriptor)
    } catch {
        logger.error("Failed to fetch workouts for training context: \(error.localizedDescription)")
        return TrainingContext()
    }

    guard !workouts.isEmpty else {
        return TrainingContext()
    }

    var muscleGroupFrequency: [String: Int] = [:]
    var recentWorkoutSummaries: [TrainingContext.WorkoutSummary] = []

    for workout in workouts {
        let exercises = (workout.exercises ?? []).sorted { $0.order < $1.order }
        var exerciseNames: [String] = []
        var muscleGroups: [String] = []
        var totalVolume: Double = 0

        for exercise in exercises {
            let name = exercise.exercise?.localizedName ?? "Unknown"
            exerciseNames.append(name)

            let group = exercise.exercise?.muscleGroup.rawValue ?? "unknown"
            if !muscleGroups.contains(group) {
                muscleGroups.append(group)
            }

            let sets = (exercise.sets ?? []).filter { $0.setType == .working }
            for set in sets {
                totalVolume += set.weight * Double(set.reps)
            }
        }

        for group in muscleGroups {
            muscleGroupFrequency[group, default: 0] += 1
        }

        let durationMinutes: Int
        if let endDate = workout.endDate {
            durationMinutes = Int(endDate.timeIntervalSince(workout.startDate) / 60)
        } else {
            durationMinutes = 0
        }

        recentWorkoutSummaries.append(
            TrainingContext.WorkoutSummary(
                date: workout.startDate,
                durationMinutes: durationMinutes,
                exerciseNames: exerciseNames,
                muscleGroups: muscleGroups,
                totalVolume: totalVolume
            )
        )
    }

    let daysSinceLastWorkout: Int?
    if let lastWorkout = workouts.first {
        daysSinceLastWorkout = Calendar.current.dateComponents(
            [.day], from: lastWorkout.startDate, to: now
        ).day
    } else {
        daysSinceLastWorkout = nil
    }

    return TrainingContext(
        recentWorkouts: recentWorkoutSummaries,
        muscleGroupFrequency: muscleGroupFrequency,
        daysSinceLastWorkout: daysSinceLastWorkout
    )
}

// MARK: - Previews

#Preview("Loading") {
    AITrainingAdviceCard(
        state: .loading,
        isExpanded: false,
        onToggleExpand: {},
        onRefresh: {}
    )
    .padding()
    .designThemePreview()
}

#Preview("Collapsed") {
    AITrainingAdviceCard(
        state: .loaded(
            TrainingRecommendation(
                title: "建议今天练背部，已休息 2 天",
                muscleGroups: ["back", "arms"],
                exercises: ["引体向上", "杠铃划船", "坐姿绳索划船"],
                reasoning: "你已经连续 2 天没有训练背部，背部肌群已充分恢复。配合臂部训练可以提高整体效率。"
            ),
            source: .fresh
        ),
        isExpanded: false,
        onToggleExpand: {},
        onRefresh: {}
    )
    .padding()
    .designThemePreview()
}

#Preview("Expanded") {
    AITrainingAdviceCard(
        state: .loaded(
            TrainingRecommendation(
                title: "建议今天练背部，已休息 2 天",
                muscleGroups: ["back", "arms"],
                exercises: ["引体向上", "杠铃划船", "坐姿绳索划船"],
                reasoning: "你已经连续 2 天没有训练背部，背部肌群已充分恢复。配合臂部训练可以提高整体效率。"
            ),
            source: .cache(generatedAt: Date().addingTimeInterval(-3600))
        ),
        isExpanded: true,
        onToggleExpand: {},
        onRefresh: {}
    )
    .padding()
    .designThemePreview()
}

#Preview("Error") {
    AITrainingAdviceCard(
        state: .error("暂时无法生成训练建议，请稍后重试。"),
        isExpanded: true,
        onToggleExpand: {},
        onRefresh: {}
    )
    .padding()
    .designThemePreview()
}
