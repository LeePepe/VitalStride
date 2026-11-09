// swiftlint:disable no_hardcoded_chinese
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedMuscleFilter: String?

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
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
                        .foregroundStyle(.primary)
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
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(String(
                localized: "正在生成替代动作…",
                comment: "Substitute sheet loading label"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
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
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    muscleFilterRail(for: recommendations)

                    ForEach(filteredRecommendations(from: recommendations)) { recommendation in
                        RecommendationCard(recommendation: recommendation) {
                            onSelect(recommendation)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .containerRelativeFrame(.horizontal)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomManualSelectBar
            }
        }
    }

    private var bottomManualSelectBar: some View {
        HStack {
            Spacer(minLength: 0)
            Button(action: onManualSelect) {
                Text(String(localized: "手动选择", comment: "Manual substitute selection"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .frame(minHeight: 38)
                    .background(
                        Color(uiColor: .secondarySystemGroupedBackground),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func filteredRecommendations(
        from recommendations: [Recommendation]
    ) -> [Recommendation] {
        guard let selectedMuscleFilter else { return recommendations }
        return recommendations.filter { $0.muscleGroup == selectedMuscleFilter }
    }

    private func muscleFilters(
        from recommendations: [Recommendation]
    ) -> [String] {
        recommendations.reduce(into: [String]()) { filters, recommendation in
            guard !filters.contains(recommendation.muscleGroup) else { return }
            filters.append(recommendation.muscleGroup)
        }
    }

    private func muscleFilterRail(
        for recommendations: [Recommendation]
    ) -> some View {
        let filters = muscleFilters(from: recommendations)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                muscleFilterChip(
                    label: String(localized: "全部", comment: "All substitute recommendation filters"),
                    value: nil
                )
                ForEach(filters, id: \.self) { filter in
                    muscleFilterChip(label: filter, value: filter)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 44)
        .accessibilityElement(children: .contain)
    }

    private func muscleFilterChip(
        label: String,
        value: String?
    ) -> some View {
        let isSelected = selectedMuscleFilter == value
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85)) {
                selectedMuscleFilter = value
            }
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .foregroundStyle(isSelected ? Color.white : .primary)
                .background(
                    isSelected
                        ? Color.accentColor
                        : Color(uiColor: .secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .overlay {
                    if !isSelected {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Error / Fallback

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(
                    Color(uiColor: .tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(String(
                localized: "无法生成智能替代",
                comment: "Substitute sheet error title"
            ))
            .font(.headline.weight(.bold))
            .foregroundStyle(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            Button(action: onManualSelect) {
                Text(String(localized: "手动选择", comment: "Manual substitute selection"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Color.white)
                    .background(
                        Color.accentColor,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: horizontalSizeClass == .regular ? 400 : .infinity)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card

private struct RecommendationCard: View {
    let recommendation: ExerciseSubstituteSheet.Recommendation
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        ViewThatFits(in: .horizontal) {
                            Text(recommendation.name)
                                .lineLimit(1)
                            Text(recommendation.name)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                        }
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: false)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)

                        Text(recommendation.muscleGroup)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(Color.accentColor)
                    }

                    Text(recommendation.reason)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
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
}

#Preview("Loading") {
    ExerciseSubstituteSheet(
        state: .loading,
        onSelect: { _ in },
        onManualSelect: {}
    )
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
}

#Preview("Empty Results") {
    ExerciseSubstituteSheet(
        state: .results([]),
        onSelect: { _ in },
        onManualSelect: {}
    )
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
}
