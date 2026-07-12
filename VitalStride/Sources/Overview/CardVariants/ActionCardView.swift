import AIService
import DesignKit
import SwiftUI

// MARK: - Small Action

struct ActionSmallCardView: View {
    let insight: OverviewInsight
    let onTap: (@Sendable () -> Void)?
    @Environment(\.theme) private var theme

    nonisolated init(insight: OverviewInsight, onTap: (@Sendable () -> Void)? = nil) {
        self.insight = insight
        self.onTap = onTap
    }

    var body: some View {
        OverviewCardContainer {
            VStack(spacing: 8) {
                if let icon = insight.iconName {
                    Image(systemName: icon)
                        .font(TypeScale.title)
                        .foregroundStyle(theme.primary.primary)
                }

                Text(insight.content)
                    .font(TypeScale.meta.weight(.medium))
                    .foregroundStyle(theme.neutrals.text1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onTap?() }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    localized: "\(insight.content), action",
                    comment: "Action card accessibility"
                )
            )
            .accessibilityAddTraits(.isButton)
        }
        .onAppear {
            if let size = insight.parsedCardSize, let type = insight.parsedCardType {
                CardTelemetry.recordRendered(size: size, type: type)
            }
        }
    }
}

// MARK: - Wide Action

struct ActionWideCardView: View {
    let insight: OverviewInsight
    let onTap: (@Sendable () -> Void)?
    @Environment(\.theme) private var theme

    nonisolated init(insight: OverviewInsight, onTap: (@Sendable () -> Void)? = nil) {
        self.insight = insight
        self.onTap = onTap
    }

    var body: some View {
        OverviewCardContainer {
            HStack(spacing: 12) {
                if let icon = insight.iconName {
                    Image(systemName: icon)
                        .font(TypeScale.display)
                        .foregroundStyle(theme.primary.primary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(TypeScale.title)
                        .foregroundStyle(theme.neutrals.text1)
                        .lineLimit(1)
                    Text(insight.content)
                        .font(TypeScale.body)
                        .foregroundStyle(theme.neutrals.text2)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    onTap?()
                } label: {
                    Text(String(localized: "action_go", defaultValue: "Go"))
                        .font(TypeScale.title)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .background(theme.primary.primary)
                        .foregroundStyle(theme.primary.onPrimary)
                        .clipShape(Capsule())
                }
                .accessibilityLabel(
                    String(
                        localized: "\(insight.title), tap to start",
                        comment: "Action button accessibility"
                    )
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if let size = insight.parsedCardSize, let type = insight.parsedCardType {
                CardTelemetry.recordRendered(size: size, type: type)
            }
        }
    }
}

#Preview("Action Small") {
    ActionSmallCardView(insight: OverviewInsight(
        key: "start_workout", cardType: "action", cardSize: "small",
        title: "Workout", content: "Start Workout", iconName: "figure.strengthtraining.traditional"
    ))
    .designThemePreview()
    .frame(width: 160)
    .padding()
}

#Preview("Action Wide") {
    ActionWideCardView(insight: OverviewInsight(
        key: "start_workout", cardType: "action", cardSize: "wide",
        title: "Time to Train",
        content: "You haven't worked out today. Start a session now!",
        iconName: "figure.strengthtraining.traditional"
    ))
    .designThemePreview()
    .padding()
}
