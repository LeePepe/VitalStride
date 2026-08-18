import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1421 — Snackbar/FAB/keyboard layout regression tests.
///
/// These tests verify two layout invariants introduced by MY-1421:
/// 1. The workout list does not shift vertically when the rest snackbar
///    appears or disappears (the FAB's safeAreaInset contribution is constant).
/// 2. While the custom numeric keyboard is visible during rest, the snackbar
///    remains fully visible by switching to the top edge.
@Suite("ActiveWorkout snackbar layout (MY-1421)")
struct ActiveWorkoutSnackbarLayoutTests {

    // MARK: - Test 1: List stability

    /// The FAB container's intrinsic height must be identical regardless of
    /// whether the bottom snackbar is showing. Before MY-1421, a conditional
    /// `.padding(.bottom, 100)` inflated the safeAreaInset height when rest
    /// was active, causing the workout list to jump. After the fix the FAB
    /// uses a constant layout size and an `.offset` for visual clearance only.
    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("FAB safeAreaInset height is constant regardless of snackbar state")
    func fabHeightConstantAcrossSnackbarStates() {
        // Measure FAB container height when snackbar is NOT visible (.none)
        let fabNoSnackbar = ActiveWorkoutFABContainer.body(snackbarSlot: .none) {
            representativeFAB
        }
        let hostNoSnackbar = UIHostingController(rootView: fabNoSnackbar)
        let sizeNoSnackbar = hostNoSnackbar.sizeThatFits(in: CGSize(width: 400, height: 0))

        // Measure FAB container height when snackbar IS visible (.rest)
        let fabWithSnackbar = ActiveWorkoutFABContainer.body(snackbarSlot: .rest) {
            representativeFAB
        }
        let hostWithSnackbar = UIHostingController(rootView: fabWithSnackbar)
        let sizeWithSnackbar = hostWithSnackbar.sizeThatFits(in: CGSize(width: 400, height: 0))

        // Also measure with undo snackbar
        let fabWithUndo = ActiveWorkoutFABContainer.body(snackbarSlot: .undo) {
            representativeFAB
        }
        let hostWithUndo = UIHostingController(rootView: fabWithUndo)
        let sizeWithUndo = hostWithUndo.sizeThatFits(in: CGSize(width: 400, height: 0))

        // All heights must match within 1pt — safeAreaInset reserved height
        // must be independent of snackbar visibility.
        let tolerance: CGFloat = 1
        #expect(
            abs(sizeNoSnackbar.height - sizeWithSnackbar.height) <= tolerance,
            "FAB height shifted by \(abs(sizeNoSnackbar.height - sizeWithSnackbar.height))pt when rest snackbar appeared; must be within \(tolerance)pt. Heights: noSnackbar=\(sizeNoSnackbar.height), withSnackbar=\(sizeWithSnackbar.height)"
        )
        #expect(
            abs(sizeNoSnackbar.height - sizeWithUndo.height) <= tolerance,
            "FAB height shifted by \(abs(sizeNoSnackbar.height - sizeWithUndo.height))pt when undo snackbar appeared; must be within \(tolerance)pt. Heights: noSnackbar=\(sizeNoSnackbar.height), withUndo=\(sizeWithUndo.height)"
        )
    }

    @MainActor
    private var representativeFAB: some View {
        Color.clear
            .frame(width: 60, height: 60)
            .padding()
    }
    #endif

    // MARK: - Test 2: Snackbar keyboard awareness

    /// When the custom numeric keyboard is visible, the snackbar must switch
    /// to the top edge so it doesn't overlap the keyboard and remains fully
    /// visible. Before MY-1421 the snackbar always used `.bottom` regardless
    /// of keyboard state.
    @Test("Snackbar edge switches to .top when keyboard is visible")
    func snackbarEdgeSwitchesToTopWithKeyboard() {
        // Without keyboard: bottom edge
        let edgeNoKeyboard = ActiveWorkoutSnackbarLayout.resolveEdge(isKeyboardVisible: false)
        #expect(edgeNoKeyboard == .bottom)

        // With keyboard: top edge so it doesn't overlap
        let edgeWithKeyboard = ActiveWorkoutSnackbarLayout.resolveEdge(isKeyboardVisible: true)
        #expect(edgeWithKeyboard == .top)
    }
}
