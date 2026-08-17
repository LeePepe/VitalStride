import DesignKit
import SwiftUI

// MARK: - ActiveWorkoutSnackbarLayout (MY-1421)

/// Pure layout-decision logic for the bottom snackbar, extracted so tests can
/// verify contracts without spinning up the full `ActiveWorkoutView`.
enum ActiveWorkoutSnackbarLayout {
    /// Determines which edge the snackbar should render at based on keyboard
    /// visibility. When the custom numeric keyboard is on screen, the snackbar
    /// moves to the top edge so it remains fully visible and never overlaps
    /// the keyboard.
    static func resolveEdge(isKeyboardVisible: Bool) -> VerticalEdge {
        isKeyboardVisible ? .top : .bottom
    }
}

// MARK: - ActiveWorkoutFABContainer (MY-1421)

/// Testable wrapper that isolates the FAB's safeAreaInset-contributing layout
/// from the rest of `ActiveWorkoutView`. The key invariant: the container's
/// intrinsic height is **constant** regardless of snackbar state — visual
/// clearance uses `.offset` (which does not affect measured size).
enum ActiveWorkoutFABContainer {
    /// The vertical offset applied to the FAB when the bottom snackbar is
    /// visible, derived from the snackbar's visual footprint:
    /// - Outer bottom padding (cardPadding = 16)
    /// - Inner vertical padding (gap = 12)
    /// - Minimum content height (minTapTarget = 44)
    /// - Inner vertical padding (gap = 12)
    /// - Visual clearance gap (cardPadding = 16)
    static let snackbarClearance: CGFloat =
        Space.cardPadding + Space.gap + Space.minTapTarget + Space.gap + Space.cardPadding

    /// Produces the FAB container view for a given snackbar state, suitable
    /// for hosting in a `UIHostingController` during tests.
    @MainActor
    static func testView(snackbarSlot: BottomSnackbarSlot) -> some View {
        fabBody(snackbarSlot: snackbarSlot)
    }

    /// The FAB layout body used both in production and tests.
    /// `.offset(y:)` shifts the button visually without changing the
    /// container's measured size — so `safeAreaInset` always reserves the
    /// same scroll inset.
    @ViewBuilder
    @MainActor
    static func fabBody(snackbarSlot: BottomSnackbarSlot) -> some View {
        // A representative 60x60 circle matching the real FAB dimensions.
        Color.clear
            .frame(width: 60, height: 60)
            .padding()
            .offset(y: snackbarSlot != .none ? -snackbarClearance : 0)
    }
}
