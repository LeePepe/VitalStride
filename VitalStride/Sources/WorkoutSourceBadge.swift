import DesignKit
import HealthKitService
import SwiftUI

/// Small source badge shown at the end of a workout row indicating where the
/// workout was recorded (this App vs an external device via HealthKit).
///
/// Design tokens: theme neutrals (background/border/text2) + `TypeScale.meta`.
/// No hardcoded colors, radii, or font sizes.
///
/// Accessibility contract: renders **decoratively** — the parent row combines
/// its label via `.accessibilityElement(children: .combine)`, so this badge
/// exposes its text through the plain `Text` sub-view and hides its glyph via
/// `.accessibilityHidden(true)`.
struct WorkoutSourceBadge: View {
    @Environment(\.theme) private var theme

    /// Coarse device kind for HealthKit-authored workouts. `nil` when the
    /// badge is rendered for an App workout (see `isApp`) or when the cached
    /// record didn't carry a device kind.
    let kind: SourceDeviceKind?

    /// Free-form `HKSourceRevision.name` fallback when `kind` is `nil`. Not
    /// shown when the badge is App-side.
    let sourceName: String?

    /// True when this badge is rendered next to a workout that VitalStride
    /// itself recorded — takes precedence over `kind` / `sourceName`.
    let isApp: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: glyphName)
                .font(.system(size: 11, weight: .medium))
                .accessibilityHidden(true)
            Text(label)
                .font(TypeScale.meta)
                .lineLimit(1)
        }
        .foregroundStyle(theme.neutrals.text2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.neutrals.inner)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.neutrals.border, lineWidth: 0.5)
        )
    }

    /// SF Symbol that best represents the source.
    private var glyphName: String {
        if isApp { return "dumbbell.fill" }
        switch kind {
        case .appleWatch: return "applewatch"
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .mac: return "laptopcomputer"
        case .other, .none: return "heart.text.square"
        }
    }

    /// Short user-facing label. `String(localized:)` catalog entries live in
    /// `Localizable.xcstrings` (keys `workout_list.source_badge.*`).
    private var label: String {
        if isApp {
            return String(
                localized: "workout_list.source_badge.app",
                defaultValue: "App",
                comment: "Workout list source badge: recorded inside VitalStride"
            )
        }
        switch kind {
        case .appleWatch:
            return String(
                localized: "workout_list.source_badge.apple_watch",
                defaultValue: "Apple Watch",
                comment: "Workout list source badge: workout came from Apple Watch"
            )
        case .iPhone:
            return String(
                localized: "workout_list.source_badge.iphone",
                defaultValue: "iPhone",
                comment: "Workout list source badge: workout came from iPhone"
            )
        case .iPad:
            return String(
                localized: "workout_list.source_badge.ipad",
                defaultValue: "iPad",
                comment: "Workout list source badge: workout came from iPad"
            )
        case .mac:
            return String(
                localized: "workout_list.source_badge.mac",
                defaultValue: "Mac",
                comment: "Workout list source badge: workout came from Mac"
            )
        case .other, .none:
            if let sourceName, !sourceName.isEmpty {
                return sourceName
            }
            return String(
                localized: "workout_list.source_badge.healthkit",
                defaultValue: "HealthKit",
                comment: "Workout list source badge: workout came from HealthKit with unknown device"
            )
        }
    }
}

extension WorkoutSourceBadge {
    /// Localised label suitable for embedding in a combined
    /// `.accessibilityLabel` on the parent row.
    static func accessibilityLabel(
        kind: SourceDeviceKind?,
        sourceName: String?,
        isApp: Bool
    ) -> String {
        if isApp {
            return String(
                localized: "workout_list.source_badge.app_a11y",
                defaultValue: "Recorded in VitalStride",
                comment: "VoiceOver: workout recorded in VitalStride app"
            )
        }
        switch kind {
        case .appleWatch:
            return String(
                localized: "workout_list.source_badge.apple_watch_a11y",
                defaultValue: "Recorded on Apple Watch",
                comment: "VoiceOver: workout came from Apple Watch"
            )
        case .iPhone:
            return String(
                localized: "workout_list.source_badge.iphone_a11y",
                defaultValue: "Recorded on iPhone",
                comment: "VoiceOver: workout came from iPhone"
            )
        case .iPad:
            return String(
                localized: "workout_list.source_badge.ipad_a11y",
                defaultValue: "Recorded on iPad",
                comment: "VoiceOver: workout came from iPad"
            )
        case .mac:
            return String(
                localized: "workout_list.source_badge.mac_a11y",
                defaultValue: "Recorded on Mac",
                comment: "VoiceOver: workout came from Mac"
            )
        case .other, .none:
            if let sourceName, !sourceName.isEmpty {
                let fmt = String(
                    localized: "workout_list.source_badge.named_source_a11y",
                    defaultValue: "Source: %@",
                    comment: "VoiceOver: workout came from a named source"
                )
                return String(format: fmt, sourceName)
            }
            return String(
                localized: "workout_list.source_badge.healthkit_a11y",
                defaultValue: "Recorded via HealthKit",
                comment: "VoiceOver: workout came from HealthKit with unknown device"
            )
        }
    }
}

#Preview("Light") {
    VStack(alignment: .leading, spacing: 12) {
        WorkoutSourceBadge(kind: nil, sourceName: nil, isApp: true)
        WorkoutSourceBadge(kind: .appleWatch, sourceName: "Apple Watch", isApp: false)
        WorkoutSourceBadge(kind: .iPhone, sourceName: "iPhone", isApp: false)
        WorkoutSourceBadge(kind: .iPad, sourceName: "iPad", isApp: false)
        WorkoutSourceBadge(kind: .mac, sourceName: "Mac", isApp: false)
        WorkoutSourceBadge(kind: .other, sourceName: "Strava", isApp: false)
        WorkoutSourceBadge(kind: nil, sourceName: nil, isApp: false)
    }
    .padding()
    .designThemePreview()
}

#Preview("Dark + accessibility3") {
    VStack(alignment: .leading, spacing: 12) {
        WorkoutSourceBadge(kind: .appleWatch, sourceName: "Apple Watch", isApp: false)
        WorkoutSourceBadge(kind: nil, sourceName: nil, isApp: true)
    }
    .padding()
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
    .designThemePreview()
}
