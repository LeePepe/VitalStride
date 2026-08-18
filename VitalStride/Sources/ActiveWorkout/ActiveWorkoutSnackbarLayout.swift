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
    /// construction: FAB is above, snackbar is below.
    ///
    /// MY-1446 P0-1 (no-list-jump): Both undo and rest content are ALWAYS
    /// laid out in a ZStack. Only the active variant has opacity and hit
    /// testing; the inactive variant is invisible but still contributes its
    /// intrinsic height. The ZStack height = max(undo, rest), which is
    /// constant across `.none`, `.undo`, and `.rest` slot transitions. This
    /// guarantees the reserved safe-area inset never changes, preserving the
    /// MY-1421 no-list-jump invariant without any magic-number clearance.
    @ViewBuilder
    @MainActor
    static func bottomSafeAreaContent<UndoContent: View, RestContent: View, FAB: View>(
        snackbarSlot: BottomSnackbarSlot,
        @ViewBuilder undoContent: () -> UndoContent,
        @ViewBuilder restContent: () -> RestContent,
        @ViewBuilder fab: () -> FAB
    ) -> some View {
        VStack(spacing: 0) {
            fab()
            ZStack(alignment: .leading) {
                undoContent()
                    .opacity(snackbarSlot == .undo ? 1 : 0)
                    .allowsHitTesting(snackbarSlot == .undo)
                restContent()
                    .opacity(snackbarSlot == .rest ? 1 : 0)
                    .allowsHitTesting(snackbarSlot == .rest)
            }
            .padding(.horizontal, Space.cardPadding)
            .padding(.vertical, Space.gap)
            .frame(maxWidth: .infinity, minHeight: Space.minTapTarget, alignment: .leading)
            .background(snackbarSlot != .none ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(
                color: snackbarSlot != .none ? .black.opacity(0.15) : .clear,
                radius: 8, y: 4
            )
            .padding(.horizontal, Space.cardPadding)
            .padding(.bottom, Space.cardPadding)
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
    /// material on supported platforms. Used by topLayout (where the card is
    /// conditionally rendered, so the old pattern is fine).
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
    /// production layout (including `.frame(minWidth: 44, minHeight: 44)` and
    /// accessibility identifiers). Extracted as a static helper so tests can
    /// verify hit targets on the actual production layout. Production calls
    /// this with themed colors and real actions.
    ///
    /// - Parameter skipTitle: The user-visible localized title for the skip
    ///   button. Required to prevent hardcoded English drift (Quality Bar G).
    @ViewBuilder
    @MainActor
    static func restTimerButtons(
        skipTitle: String,
        neutralBackground: Color = Color.gray.opacity(0.15),
        skipBackground: Color = Color.blue.opacity(0.15),
        minus10AccessibilityLabel: String = "-10s",
        plus10AccessibilityLabel: String = "+10s",
        skipAccessibilityLabel: String = "Skip",
        onMinus10: @escaping () -> Void = {},
        onPlus10: @escaping () -> Void = {},
        onSkip: @escaping () -> Void = {}
    ) -> some View {
        HStack(spacing: 8) {
            Button("-10s", action: onMinus10)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(neutralBackground, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
                .accessibilityIdentifier("rest_button_minus10")
                .accessibilityLabel(minus10AccessibilityLabel)
            Button("+10s", action: onPlus10)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(neutralBackground, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
                .accessibilityIdentifier("rest_button_plus10")
                .accessibilityLabel(plus10AccessibilityLabel)
            Button(skipTitle, action: onSkip)
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(skipBackground, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Capsule())
                .accessibilityIdentifier("rest_button_skip")
                .accessibilityLabel(skipAccessibilityLabel)
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
