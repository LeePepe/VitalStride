import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1446 — Snackbar safe-area regression tests.
///
/// Verifies layout invariants that use safe area as single truth source:
/// 1. The FAB and bottom snackbar frames must not intersect (VStack proof).
/// 2. The bottom snackbar must be fully contained within the safe area
///    (not clipped by the home indicator region).
/// 3. When the snackbar is at the top edge (keyboard visible), it must not
///    cause a list jump (constant-height proof via topLayout).
/// 4. Each rest timer button (Skip, -10s, +10s) has a hit target >= 44×44pt
///    verified on the production `restTimerButton` helper.
/// 5. The bottom safe-area content reserved height is constant across all slot
///    states (preserves MY-1421 no-list-jump invariant on the production path).
///
/// Tests use `sizeThatFits`-based measurement (not UIKit view hierarchy
/// traversal) for reliable cross-simulator results.
@Suite("ActiveWorkout snackbar safe-area layout (MY-1446)")
struct ActiveWorkoutSnackbarSafeAreaTests {

    // MARK: - Test 1: FAB and bottom snackbar non-overlapping

    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("Bottom snackbar and FAB frames do not intersect (VStack construction)")
    func bottomSnackbarAndFABDoNotIntersect() {
        let containerWidth: CGFloat = 393

        // Measure FAB alone
        let fabHost = UIHostingController(rootView: fabPlaceholder)
        let fabSize = fabHost.sizeThatFits(in: CGSize(width: containerWidth, height: .infinity))

        // Measure snackbar envelope alone (rest slot content)
        let snackbarHost = UIHostingController(rootView: productionRestContent(completed: false))
        let snackbarSize = snackbarHost.sizeThatFits(in: CGSize(width: containerWidth, height: .infinity))

        // Measure combined bottomSafeAreaContent
        let combined = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: .rest,
            undoContent: { undoPlaceholder },
            restContent: { productionRestContent(completed: false) },
            fab: { fabPlaceholder }
        )
        let combinedHost = UIHostingController(rootView: combined)
        let combinedSize = combinedHost.sizeThatFits(in: CGSize(width: containerWidth, height: .infinity))

        // VStack height must be >= both individual heights (proving both render
        // and are stacked, not overlapping).
        #expect(combinedSize.height > fabSize.height)
        #expect(combinedSize.height > snackbarSize.height)
        // Combined >= fab + snackbar (they share no space in VStack)
        #expect(combinedSize.height >= fabSize.height + snackbarSize.height - 1)
    }

    // MARK: - Test 2: snackbar within safe area (non-zero inset)

    /// Uses a UIWindow with `additionalSafeAreaInsets` to simulate a real
    /// home-indicator region (34pt). The combined layout must fit within
    /// the available safe area.
    @MainActor
    @Test("Bottom snackbar does not invade home indicator region")
    func bottomSnackbarWithinSafeArea() {
        let layout = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: .rest,
            undoContent: { undoPlaceholder },
            restContent: { productionRestContent(completed: false) },
            fab: { fabPlaceholder }
        )
        let host = UIHostingController(rootView: layout)
        // Simulate iPhone with 34pt bottom safe area (home indicator)
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)

        // Place inside a window for proper safe area propagation
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        // The content should fit within the safe area (above the 34pt zone).
        let contentSize = host.sizeThatFits(in: CGSize(width: 393, height: .infinity))
        let safeAreaHeight = 600.0 - 34.0

        #expect(contentSize.height <= safeAreaHeight + 1)

        // Verify that safe area insets were actually applied
        let appliedInsets = host.view.safeAreaInsets
        #expect(appliedInsets.bottom >= 34)

        window.isHidden = true
    }

    // MARK: - Test 3: top snackbar constant height (no-list-jump for keyboard path)

    /// MY-1446 P0-2: The `topLayout` helper uses opacity to show/hide the
    /// snackbar. The VStack height must be constant whether the slot is `.none`,
    /// `.undo`, or `.rest`, proving the list does not jump when the snackbar
    /// toggles during keyboard visibility.
    @MainActor
    @Test("Top snackbar layout height is constant across slot states (no-list-jump)")
    func topSnackbarDoesNotCoverInfoBand() {
        let containerWidth: CGFloat = 393

        // Measure for each slot state using the production topLayout helper
        // with the same content production uses (bottomSnackbarContent)
        let noneHeight = measureTopLayoutHeight(slot: .none, width: containerWidth)
        let undoHeight = measureTopLayoutHeight(slot: .undo, width: containerWidth)
        let restHeight = measureTopLayoutHeight(slot: .rest, width: containerWidth)

        let tolerance: CGFloat = 1
        #expect(abs(noneHeight - undoHeight) <= tolerance)
        #expect(abs(noneHeight - restHeight) <= tolerance)
        #expect(abs(undoHeight - restHeight) <= tolerance)
    }

    // MARK: - Test 4: production rest timer buttons each >= 44pt in both dimensions

    /// Tests each production button individually using
    /// `ActiveWorkoutSnackbarLayout.restTimerButton` — the same builder
    /// that `restTimerButtons` uses internally. This covers the production
    /// code path without relying on SwiftUI→UIView identifier propagation.
    @MainActor
    @Test("Rest timer buttons layout provides >=44pt minimum hit targets")
    func restTimerButtonsHitTargets() {
        // Verify the composite HStack meets minimum requirements
        let content = ActiveWorkoutSnackbarLayout.restTimerButtons(skipTitle: "跳过")
        let host = UIHostingController(rootView: content)
        let size = host.sizeThatFits(in: CGSize(width: 393, height: .infinity))
        #expect(size.height >= 44)
        #expect(size.width >= 44 * 3 + 8 * 2)

        // Verify each production button individually meets 44×44pt
        let buttonSpecs: [(title: String, isBold: Bool, id: String, label: String)] = [
            ("-10s", false, "rest_button_minus10", "-10s"),
            ("+10s", false, "rest_button_plus10", "+10s"),
            ("跳过", true, "rest_button_skip", "Skip"),
        ]
        for spec in buttonSpecs {
            let button = ActiveWorkoutSnackbarLayout.restTimerButton(
                title: spec.title,
                isBold: spec.isBold,
                accessibilityIdentifier: spec.id,
                accessibilityLabel: spec.label
            )
            let buttonHost = UIHostingController(rootView: button)
            let buttonSize = buttonHost.sizeThatFits(in: CGSize(width: 200, height: .infinity))
            #expect(buttonSize.height >= 44)
            #expect(buttonSize.width >= 44)
        }
    }

    // MARK: - Test 5: No-list-jump — bottomSafeAreaContent height is constant (production content)

    /// MY-1446 P0-1 regression: the production `bottomSafeAreaContent` uses a
    /// ZStack envelope with both undo and rest content always laid out.
    /// This test verifies the height is constant across all slot states using
    /// real production-representative content:
    /// - undo: uses `ActiveWorkoutSnackbarLayout.undoEnvelope` (the same helper
    ///   production calls) with a long message that exceeds 2 lines at AX sizes
    /// - rest: completed banner + resting progress + buttons
    /// Tests at both default and large Dynamic Type sizes.
    @MainActor
    @Test("bottomSafeAreaContent height is constant across all slot states (no-list-jump)")
    func bottomSafeAreaContentHeightConstant() {
        let sizeCategories: [UIContentSizeCategory] = [.medium, .accessibilityExtraLarge]

        for sizeCategory in sizeCategories {
            let noneHeight = measureSlotHeight(slot: .none, sizeCategory: sizeCategory)
            let undoHeight = measureSlotHeight(slot: .undo, sizeCategory: sizeCategory)
            let restHeight = measureSlotHeight(slot: .rest, sizeCategory: sizeCategory)

            let tolerance: CGFloat = 1
            #expect(abs(noneHeight - undoHeight) <= tolerance)
            #expect(abs(noneHeight - restHeight) <= tolerance)
            #expect(abs(undoHeight - restHeight) <= tolerance)
        }
    }

    // MARK: - Measurement helpers

    /// Measures the height of `topLayout` for a given slot. Uses a ZStack
    /// envelope with both undo and rest content always laid out (matching
    /// production `topSnackbarEnvelope`), proving height is slot-independent.
    @MainActor
    private func measureTopLayoutHeight(slot: BottomSnackbarSlot, width: CGFloat) -> CGFloat {
        // Mirror the production topSnackbarEnvelope: both variants always
        // laid out, opacity-toggled by slot.
        let envelope = ZStack(alignment: .leading) {
            productionUndoContent(
                message: "Deleted Warmup sub-set of set 10 in superset group A"
            )
            .opacity(slot == .undo ? 1 : 0)
            productionRestContent(completed: false)
                .opacity(slot == .rest ? 1 : 0)
        }
        let layout = ActiveWorkoutSnackbarLayout.topLayout(
            snackbarSlot: slot,
            snackbar: { envelope }
        )
        let host = UIHostingController(rootView: layout)
        return host.sizeThatFits(in: CGSize(width: width, height: .infinity)).height
    }

    /// Measures the height of `bottomSafeAreaContent` for a given slot at a
    /// specific Dynamic Type size. Uses a real parent/child controller
    /// relationship so `setOverrideTraitCollection` actually propagates.
    @MainActor
    private func measureSlotHeight(
        slot: BottomSnackbarSlot,
        sizeCategory: UIContentSizeCategory
    ) -> CGFloat {
        let layout = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: slot,
            undoContent: {
                // Use a long multiline message that would exceed 2 lines at
                // accessibility sizes if lineLimit were not enforced.
                productionUndoContent(
                    message: "Deleted Warmup sub-set of set 10 in superset group A (bicep curls)"
                )
            },
            restContent: {
                productionRestContent(completed: slot == .rest)
            },
            fab: { fabPlaceholder }
        )
        let host = UIHostingController(rootView: layout)
        host.overrideUserInterfaceStyle = .light

        // Use a parent controller so setOverrideTraitCollection propagates
        let parent = UIViewController()
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)

        // Apply Dynamic Type size category via parent/child relationship
        let traits = UITraitCollection(preferredContentSizeCategory: sizeCategory)
        parent.setOverrideTraitCollection(traits, forChild: host)

        let size = host.sizeThatFits(in: CGSize(width: 393, height: .infinity))

        // Clean up
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()

        return size.height
    }

    // MARK: - Helpers

    /// Production-representative undo content. Uses the actual production
    /// `ActiveWorkoutSnackbarLayout.undoEnvelope` helper — the same code path
    /// that `ActiveWorkoutView.undoSnackbarEnvelope` calls.
    @MainActor
    @ViewBuilder
    private func productionUndoContent(message: String) -> some View {
        ActiveWorkoutSnackbarLayout.undoEnvelope(
            message: message
        )
    }

    /// Production-representative rest content. Uses a ZStack with hidden sizing
    /// reference (mirrors `restSnackbarEnvelope`). When `completed` is true,
    /// shows the shorter completed banner; the sizing reference ensures height
    /// stays stable regardless.
    @MainActor
    @ViewBuilder
    private func productionRestContent(completed: Bool = false) -> some View {
        ZStack(alignment: .leading) {
            // Hidden sizing reference: progress circle + buttons
            HStack {
                Circle()
                    .stroke(Color.gray, lineWidth: 3)
                    .frame(width: 32, height: 32)
                Spacer()
                ActiveWorkoutSnackbarLayout.restTimerButtons(skipTitle: "跳过")
            }
            .hidden()

            // Active content
            if completed {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("休息结束")
                    Spacer()
                }
            } else {
                HStack {
                    Circle()
                        .stroke(Color.gray, lineWidth: 3)
                        .frame(width: 32, height: 32)
                    Spacer()
                    ActiveWorkoutSnackbarLayout.restTimerButtons(skipTitle: "跳过")
                }
            }
        }
    }

    /// Placeholder for the undo variant in tests that don't exercise undo content.
    @MainActor
    private var undoPlaceholder: some View {
        productionUndoContent(message: "Deleted set 1 of superset group B (tricep extensions warmup)")
    }

    @MainActor
    private var fabPlaceholder: some View {
        Circle()
            .fill(Color.green.opacity(0.3))
            .frame(width: 60, height: 60)
            .padding()
    }
    #endif
}

// MARK: - Snackbar slot arbitration regression tests (MY-1446)

@Suite("BottomSnackbarSlot arbitration (MY-1446)")
struct BottomSnackbarSlotArbitrationTests {
    @Test("Undo outranks rest-completed: slot stays .undo when rest completes during undo window")
    func undoOutranksRestCompleted() {
        let slot = BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .completed)
        #expect(slot == .undo, "Undo must outrank rest-completed; got \(slot)")
    }

    @Test("Rest shows once undo clears")
    func restShowsAfterUndoClears() {
        let slot = BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .completed)
        #expect(slot == .rest, "Rest-completed must show once undo clears; got \(slot)")
    }

    @Test("No snackbar when idle and no undo")
    func noSnackbarWhenIdle() {
        let slot = BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .idle)
        #expect(slot == .none)
    }

    @Test("Undo outranks resting phase")
    func undoOutranksResting() {
        let slot = BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .resting)
        #expect(slot == .undo)
    }
}
