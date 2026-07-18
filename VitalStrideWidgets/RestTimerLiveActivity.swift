import ActivityKit
import SwiftUI
import WidgetKit

struct RestTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestTimerAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                DynamicIslandExpandedRegion(.center) {
                    expandedContent(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    EmptyView()
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Color.accentColor)
            } compactTrailing: {
                compactTrailingContent(context: context)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<RestTimerAttributes>) -> some View {
        let state = context.state
        if state.isEffectivelyCompleted() {
            completedLockScreen()
        } else {
            restingLockScreen(state: state)
        }
    }

    @ViewBuilder
    private func restingLockScreen(state: RestTimerAttributes.ContentState) -> some View {
        if let remaining = state.remainingInterval(),
           let progress = state.progressInterval() {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(Color.accentColor)
                    Text("rest_live_activity_title", comment: "Live Activity lock screen title")
                        .font(.headline)
                    Spacer()
                    Text(timerInterval: remaining, countsDown: true)
                        .font(.title2.monospacedDigit())
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.trailing)
                }
                ProgressView(timerInterval: progress, countsDown: false)
                    .tint(Color.accentColor)
                    .accessibilityHidden(true)
            }
            .padding()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text("rest_live_activity_a11y_label", comment: "Live Activity a11y: Resting")
            )
            .accessibilityValue(
                Text(timerInterval: remaining, countsDown: true)
            )
        } else {
            // Fallback: state became invalid (expired / zero duration) between
            // the lockScreenView guard and this render pass. Render the
            // completed view rather than constructing an illegal range.
            completedLockScreen()
        }
    }

    private func completedLockScreen() -> some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            Text("rest_live_activity_completed", comment: "Live Activity completed text")
                .font(.headline)
            Spacer()
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("rest_live_activity_completed_a11y", comment: "Live Activity completed a11y")
        )
    }

    // MARK: - Dynamic Island Expanded

    private func expandedContent(context: ActivityViewContext<RestTimerAttributes>) -> some View {
        let state = context.state
        return VStack(spacing: 4) {
            Text("rest_live_activity_title", comment: "Live Activity DI expanded title")
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.phase == .resting,
               let remaining = state.remainingInterval(),
               let progress = state.progressInterval() {
                Text(timerInterval: remaining, countsDown: true)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.semibold)
                ProgressView(timerInterval: progress, countsDown: false)
                    .tint(Color.accentColor)
                    .accessibilityHidden(true)
            } else {
                Text("rest_live_activity_completed", comment: "Live Activity DI completed")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("rest_live_activity_a11y_label", comment: "DI expanded a11y label")
        )
    }

    // MARK: - Dynamic Island Compact Trailing

    private func compactTrailingContent(context: ActivityViewContext<RestTimerAttributes>) -> some View {
        let state = context.state
        return Group {
            if state.phase == .resting,
               let remaining = state.remainingInterval() {
                Text(timerInterval: remaining, countsDown: true)
                    .monospacedDigit()
                    .font(.caption2)
                    .frame(minWidth: 32)
                    .accessibilityLabel(
                        Text("rest_live_activity_compact_a11y", comment: "DI compact remaining a11y")
                    )
                    .accessibilityValue(
                        Text(timerInterval: remaining, countsDown: true)
                    )
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel(
                        Text("rest_live_activity_completed_a11y", comment: "DI compact completed a11y")
                    )
            }
        }
    }
}
