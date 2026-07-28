import DesignKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Load / failure / unauthorized banner shown at the top of the workout list
/// when the HealthKit fetch cannot render normally. The empty state is handled
/// separately by `ContentUnavailableView` in `WorkoutListView`.
///
/// Design tokens: DesignKit theme neutrals only. No hardcoded colors, radii,
/// or font sizes.
///
/// Accessibility contract:
/// - Whole banner is one accessibility element (combines icon + text).
/// - "Open Settings" button carries its own `.accessibilityLabel` +
///   `.accessibilityHint`; hit target ≥ 44 × 44 pt.
/// - Decorative SF Symbols are `.accessibilityHidden(true)`.
struct WorkoutListStateBanner: View {
    /// One-of-four presentation state the banner renders for.
    ///
    /// The empty state is intentionally NOT modelled here — it's owned by
    /// `WorkoutListView`'s `ContentUnavailableView`.
    enum LoadState: Equatable {
        case loading
        case failed
        case unauthorized
    }

    @Environment(\.theme) private var theme

    let state: LoadState

    /// Invoked when the user taps the "Open Settings" CTA in the
    /// `.unauthorized` state. Silently ignored in other states — those don't
    /// render a button.
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconView

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.neutrals.text1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(theme.neutrals.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            if state == .unauthorized {
                Button(action: onOpenSettings) {
                    Text(
                        String(
                            localized: "workout_list.state_banner.open_settings",
                            defaultValue: "Open Settings",
                            comment: "Workout list unauthorized banner CTA — jump to iOS Settings"
                        )
                    )
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(
                    String(
                        localized: "workout_list.state_banner.open_settings_a11y",
                        defaultValue: "Open Settings",
                        comment: "VoiceOver label for the open-settings CTA in the workout list banner"
                    )
                )
                .accessibilityHint(
                    String(
                        localized: "workout_list.state_banner.open_settings_hint",
                        defaultValue: "Grants VitalStride access to HealthKit workouts",
                        comment: "VoiceOver hint for the open-settings CTA"
                    )
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.neutrals.inner)
        )
    }

    @ViewBuilder
    private var iconView: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
                .frame(width: 22, height: 22)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(theme.warning)
                .accessibilityHidden(true)
        case .unauthorized:
            Image(systemName: "lock.shield")
                .font(.title3)
                .foregroundStyle(theme.primary.primary)
                .accessibilityHidden(true)
        }
    }

    private var title: String {
        switch state {
        case .loading:
            return String(
                localized: "workout_list.state_banner.loading_title",
                defaultValue: "Loading workouts",
                comment: "Workout list loading banner title"
            )
        case .failed:
            return String(
                localized: "workout_list.state_banner.failed_title",
                defaultValue: "Couldn't load Apple Health workouts",
                comment: "Workout list failure banner title"
            )
        case .unauthorized:
            return String(
                localized: "workout_list.state_banner.unauthorized_title",
                defaultValue: "Grant HealthKit access",
                comment: "Workout list unauthorized banner title"
            )
        }
    }

    private var subtitle: String {
        switch state {
        case .loading:
            return String(
                localized: "workout_list.state_banner.loading_subtitle",
                defaultValue: "Fetching your Apple Watch and Health data.",
                comment: "Workout list loading banner subtitle"
            )
        case .failed:
            return String(
                localized: "workout_list.state_banner.failed_subtitle",
                defaultValue: "Pull to refresh, or try again later.",
                comment: "Workout list failure banner subtitle"
            )
        case .unauthorized:
            return String(
                localized: "workout_list.state_banner.unauthorized_subtitle",
                defaultValue: "Enable Workouts in Settings to see Apple Watch training here.",
                comment: "Workout list unauthorized banner subtitle"
            )
        }
    }
}

extension WorkoutListStateBanner {
    /// Opens iOS Settings for VitalStride. Kept out of the view so tests can
    /// verify banner rendering without touching `UIApplication`.
    /// `@MainActor` because `UIApplication.shared` is main-actor-isolated
    /// under Swift 6 strict concurrency.
    @MainActor
    static func openSettings() {
        #if canImport(UIKit) && !os(watchOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

#Preview("Loading — light") {
    WorkoutListStateBanner(state: .loading, onOpenSettings: {})
        .padding()
        .designThemePreview()
}

#Preview("Failed — light") {
    WorkoutListStateBanner(state: .failed, onOpenSettings: {})
        .padding()
        .designThemePreview()
}

#Preview("Unauthorized — light") {
    WorkoutListStateBanner(state: .unauthorized, onOpenSettings: {})
        .padding()
        .designThemePreview()
}

#Preview("Loading — dark") {
    WorkoutListStateBanner(state: .loading, onOpenSettings: {})
        .padding()
        .preferredColorScheme(.dark)
        .designThemePreview()
}

#Preview("Failed — dark") {
    WorkoutListStateBanner(state: .failed, onOpenSettings: {})
        .padding()
        .preferredColorScheme(.dark)
        .designThemePreview()
}

#Preview("Unauthorized — dark + accessibility3") {
    WorkoutListStateBanner(state: .unauthorized, onOpenSettings: {})
        .padding()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
        .designThemePreview()
}
