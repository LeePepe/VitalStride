import AIService
import SwiftUI

// MARK: - Small Action

struct ActionSmallCardView: View {
    let insight: OverviewInsight
    let onTap: (@Sendable () -> Void)?

    init(insight: OverviewInsight, onTap: (@Sendable () -> Void)? = nil) {
        self.insight = insight
        self.onTap = onTap
    }

    var body: some View {
        OverviewCardContainer {
            VStack(spacing: 8) {
                if let icon = insight.iconName {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.blue)
                }

                Text(insight.content)
                    .font(.caption.weight(.medium))
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
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }
}

// MARK: - Wide Action

struct ActionWideCardView: View {
    let insight: OverviewInsight
    let onTap: (@Sendable () -> Void)?

    init(insight: OverviewInsight, onTap: (@Sendable () -> Void)? = nil) {
        self.insight = insight
        self.onTap = onTap
    }

    var body: some View {
        OverviewCardContainer {
            HStack(spacing: 12) {
                if let icon = insight.iconName {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(insight.content)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    onTap?()
                } label: {
                    Text(String(localized: "action_go", defaultValue: "Go"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.blue)
                        .foregroundStyle(.white)
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
            CardTelemetry.recordRendered(size: insight.cardSize, type: insight.cardType)
        }
    }
}

#Preview("Action Small") {
    ActionSmallCardView(insight: OverviewInsight(
        key: "start_workout", cardType: "action", cardSize: "small",
        title: "Workout", content: "Start Workout", iconName: "figure.strengthtraining.traditional"
    ))
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
    .padding()
}
