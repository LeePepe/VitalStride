// swiftlint:disable no_hardcoded_chinese
import DesignKit
import SwiftUI

/// UI shell for the AI substitute-exercise flow.
///
/// The sheet is fully driven by ``ViewState`` and two callbacks: it does not
/// invoke the AI provider, SwiftData, or dismissal itself — the parent view
/// owns state, presentation, and side effects. This keeps T012 scope limited
/// to the presentational layer and preserves per-state previewability.
struct ExerciseSubstituteSheet: View {
    /// A single AI-recommended substitute rendered as a card.
    struct Recommendation: Identifiable, Equatable, Sendable {
        /// Stable identifier used by SwiftUI (and by the parent to disambiguate
        /// selections). Typically the AI-returned `exerciseId`.
        let id: String
        let name: String
        let muscleGroup: String
        let reason: String
    }

    /// Deterministic view states the parent flips between.
    enum ViewState: Equatable, Sendable {
        case loading
        case results([Recommendation])
        case error(message: String)
    }

    let state: ViewState
    let onSelect: (Recommendation) -> Void
    let onManualSelect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.neutrals.bg)
                .navigationTitle(String(
                    localized: "智能替代",
                    comment: "Substitute exercise sheet navigation title"
                ))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(
                            localized: "取消",
                            comment: "Substitute sheet cancel button"
                        )) {
                            dismiss()
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            loadingView
        case .results(let recommendations):
            resultsView(recommendations)
        case .error(let message):
            errorView(message: message)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(String(
                localized: "正在生成替代动作…",
                comment: "Substitute sheet loading label"
            ))
            .font(.subheadline)
            .foregroundStyle(theme.neutrals.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Results

    @ViewBuilder
    private func resultsView(_ recommendations: [Recommendation]) -> some View {
        if recommendations.isEmpty {
            errorView(message: String(
                localized: "暂无同肌群替代建议，可手动选择动作。",
                comment: "Substitute sheet empty-results fallback message"
            ))
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(
                        localized: "AI 推荐的同肌群替代",
                        comment: "Substitute sheet results header"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
                    .padding(.horizontal, 4)

                    ForEach(recommendations) { recommendation in
                        RecommendationCard(recommendation: recommendation) {
                            onSelect(recommendation)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Error / Fallback

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(theme.neutrals.text2)
                .accessibilityHidden(true)

            Text(String(
                localized: "无法生成智能替代",
                comment: "Substitute sheet error title"
            ))
            .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.neutrals.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                onManualSelect()
            } label: {
                Text(String(
                    localized: "手动选择",
                    comment: "Substitute sheet manual-select button"
                ))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Card

private struct RecommendationCard: View {
    @Environment(\.theme) private var theme
    let recommendation: ExerciseSubstituteSheet.Recommendation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(recommendation.name)
                        .font(.headline)
                        .foregroundStyle(theme.neutrals.text1)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Text(recommendation.muscleGroup)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(theme.primary.primary.opacity(0.12))
                        .foregroundStyle(theme.primary.primary)
                        .clipShape(Capsule())
                }

                Text(recommendation.reason)
                    .font(.subheadline)
                    .foregroundStyle(theme.neutrals.text2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(theme.neutrals.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(theme.neutrals.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(String(
            localized: "\(recommendation.name)，主肌群 \(recommendation.muscleGroup)",
            comment: "Substitute recommendation a11y label: name + primary muscle"
        )))
        .accessibilityHint(Text(String(
            localized: "点按替换为该动作",
            comment: "Substitute recommendation a11y hint"
        )))
    }
}

// MARK: - Previews

#Preview("Results") {
    ExerciseSubstituteSheet(
        state: .results([
            ExerciseSubstituteSheet.Recommendation(
                id: "incline-dumbbell-press",
                name: String(localized: "上斜哑铃卧推", comment: ""),
                muscleGroup: String(localized: "胸", comment: ""),
                reason: String(localized: "同为胸大肌上部主导，无杠铃时可平替。", comment: "")
            ),
            ExerciseSubstituteSheet.Recommendation(
                id: "machine-chest-press",
                name: String(localized: "器械胸推", comment: ""),
                muscleGroup: String(localized: "胸", comment: ""),
                reason: String(localized: "轨迹固定、稳定性要求低，肩伤时更安全。", comment: "")
            ),
            ExerciseSubstituteSheet.Recommendation(
                id: "push-up",
                name: String(localized: "俯卧撑", comment: ""),
                muscleGroup: String(localized: "胸", comment: ""),
                reason: String(localized: "自重完成，无器械环境可用。", comment: "")
            ),
        ]),
        onSelect: { _ in },
        onManualSelect: {}
    )
    .designThemePreview()
}

#Preview("Loading") {
    ExerciseSubstituteSheet(
        state: .loading,
        onSelect: { _ in },
        onManualSelect: {}
    )
    .designThemePreview()
}

#Preview("Error") {
    ExerciseSubstituteSheet(
        state: .error(message: String(
            localized: "AI 暂不可用，请手动选择替代动作。",
            comment: "Substitute sheet error preview message"
        )),
        onSelect: { _ in },
        onManualSelect: {}
    )
    .designThemePreview()
}

#Preview("Empty Results") {
    ExerciseSubstituteSheet(
        state: .results([]),
        onSelect: { _ in },
        onManualSelect: {}
    )
    .designThemePreview()
}

#Preview("Results — Dark") {
    ExerciseSubstituteSheet(
        state: .results([
            ExerciseSubstituteSheet.Recommendation(
                id: "seated-cable-row",
                name: String(localized: "坐姿绳索划船", comment: ""),
                muscleGroup: String(localized: "背", comment: ""),
                reason: String(localized: "同为背阔肌水平拉主导，轨迹稳定。", comment: "")
            ),
            ExerciseSubstituteSheet.Recommendation(
                id: "one-arm-dumbbell-row",
                name: String(localized: "单臂哑铃划船", comment: ""),
                muscleGroup: String(localized: "背", comment: ""),
                reason: String(localized: "单侧发力，纠正左右不平衡。", comment: "")
            ),
            ExerciseSubstituteSheet.Recommendation(
                id: "chest-supported-row",
                name: String(localized: "俯身支撑划船", comment: ""),
                muscleGroup: String(localized: "背", comment: ""),
                reason: String(localized: "去除腰椎代偿，可加大离心。", comment: "")
            ),
        ]),
        onSelect: { _ in },
        onManualSelect: {}
    )
    .preferredColorScheme(.dark)
    .designThemePreview()
}
