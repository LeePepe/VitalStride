import DesignKit
import SwiftUI

// MARK: - ActiveWorkoutSnackbarLayout (MY-1421, MY-1446)

/// Pure layout-decision logic for the snackbar, extracted so tests can
/// verify contracts without spinning up the full `ActiveWorkoutView`.
///
/// MY-1446: extended to provide safe-area-driven rendering that guarantees
/// non-overlap between snackbar, FAB, and info band by construction (VStack).
enum ActiveWorkoutSnackbarLayout {
    /// Determines which edge the snackbar should render at based on keyboard
    /// visibility. When the custom numeric keyboard is on screen, the snackbar
    /// moves to the top edge so it remains fully visible and never overlaps
    /// the keyboard.
    static func resolveEdge(isKeyboardVisible: Bool) -> VerticalEdge {
        isKeyboardVisible ? .top : .bottom
    }

    // MARK: - Bottom safe-area content (MY-1446)

    /// Renders the combined bottom layout for the `safeAreaInset(edge: .bottom)`.
    /// Uses a VStack to guarantee the FAB and snackbar never overlap by
    /// construction: FAB is above, snackbar is below. The total height is the
    /// single source of truth for the list's bottom scroll inset.
    ///
    /// When `snackbarSlot == .none`, only the FAB is rendered. When a snackbar
    /// is active, it appears below the FAB with standard card styling.
    @ViewBuilder
    @MainActor
    static func bottomSafeAreaContent<Snackbar: View, FAB: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder snackbar: () -> Snackbar,
        @ViewBuilder fab: () -> FAB
    ) -> some View {
        VStack(spacing: 0) {
            fab()
            if snackbarSlot != .none {
                snackbar()
                    .padding(.horizontal, Space.cardPadding)
                    .padding(.vertical, Space.gap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(snackbarCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.horizontal, Space.cardPadding)
                    .padding(.bottom, Space.cardPadding)
            }
        }
    }

    // MARK: - Top layout (MY-1446)

    /// Renders the info band + top snackbar stacked vertically. The snackbar
    /// appears BELOW the info band, guaranteeing non-overlap by construction.
    /// Used when the keyboard is visible and the snackbar must be at the top
    /// edge without covering the persistent info band.
    @ViewBuilder
    @MainActor
    static func topLayout<InfoBand: View, Snackbar: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder infoBand: () -> InfoBand,
        @ViewBuilder snackbar: () -> Snackbar
    ) -> some View {
        VStack(spacing: 0) {
            infoBand()
            if snackbarSlot != .none {
                snackbar()
                    .padding(.horizontal, Space.cardPadding)
                    .padding(.vertical, Space.gap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(snackbarCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: -4)
                    .padding(.horizontal, Space.cardPadding)
                    .padding(.top, Space.inline)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// The visual background for the snackbar card. Uses the system `.bar`
    /// material on supported platforms.
    @ViewBuilder
    @MainActor
    private static var snackbarCardBackground: some View {
        #if os(watchOS)
        Color.gray.opacity(0.25)
        #else
        Color.clear.background(.bar)
        #endif
    }

    // MARK: - Rest timer button layout (MY-1446, testable)

    /// Renders the rest timer adjust buttons (-10s, +10s, Skip) with the
    /// production layout (including `.frame(minHeight: 44)` and accessibility
    /// identifiers). Extracted as a static helper so tests can verify hit
    /// targets on the actual production layout without depending on
    /// `ActiveWorkoutView`'s private properties.
    @ViewBuilder
    @MainActor
    static func restTimerButtons(
        onMinus10: @escaping () -> Void = {},
        onPlus10: @escaping () -> Void = {},
        onSkip: @escaping () -> Void = {}
    ) -> some View {
        HStack(spacing: 8) {
            Button("-10s", action: onMinus10)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.15), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .accessibilityIdentifier("rest_button_minus10")
            Button("+10s", action: onPlus10)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.15), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .accessibilityIdentifier("rest_button_plus10")
            Button("Skip", action: onSkip)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.15), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Capsule())
                .accessibilityIdentifier("rest_button_skip")
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ActiveWorkoutFABContainer (MY-1421)

/// Testable wrapper that isolates the FAB's safeAreaInset-contributing layout
/// from the rest of `ActiveWorkoutView`. The key invariant: the container's
/// intrinsic height is **constant** regardless of snackbar state.
///
/// MY-1446: the offset hack is removed. The FAB's position is now constant
/// because the snackbar occupies its own distinct region below the FAB
/// (via the unified `bottomSafeAreaContent` VStack). The `snackbarSlot`
/// parameter is preserved for API stability and test compatibility.
enum ActiveWorkoutFABContainer {
    /// Snackbar clearance constant — retained for backward compatibility with
    /// existing tests and any code that references it.
    static let snackbarClearance: CGFloat =
        Space.cardPadding + Space.gap + Space.minTapTarget + Space.gap + Space.cardPadding

    /// The FAB layout body. Intrinsic height is constant regardless of
    /// snackbar state (the `snackbarSlot` parameter no longer affects layout).
    @ViewBuilder
    @MainActor
    static func body<Content: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
    }
}
