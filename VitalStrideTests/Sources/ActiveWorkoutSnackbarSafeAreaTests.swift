import DesignKit
import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1446 — Snackbar safe-area regression tests.
///
/// Verifies layout invariants that use safe area as single truth source:
/// 1. The FAB and bottom snackbar frames must not intersect.
/// 2. The bottom snackbar must be fully contained within the safe area
///    (not clipped by the home indicator region).
/// 3. When the snackbar is at the top edge (keyboard visible), it must not
///    overlap the persistent compact info band.
/// 4. Each rest timer button (Skip, -10s, +10s) has a hit target >= 44×44pt.
/// 5. The bottom safe-area content reserved height is constant across all slot
///    states (preserves MY-1421 no-list-jump invariant on the production path).
///
/// These tests exercise `ActiveWorkoutSnackbarLayout` helpers — the same
/// helpers called by production `ActiveWorkoutView`.
@Suite("ActiveWorkout snackbar safe-area layout (MY-1446)")
struct ActiveWorkoutSnackbarSafeAreaTests {

    // MARK: - Test 1: FAB and bottom snackbar non-overlapping

    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("Bottom snackbar and FAB frames do not intersect")
    func bottomSnackbarAndFABDoNotIntersect() {
        let layout = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: .rest,
            undoContent: { undoPlaceholder },
            restContent: { snackbarPlaceholder },
            fab: { fabPlaceholder }
        )
        let host = UIHostingController(rootView: layout)
        let containerSize = CGSize(width: 393, height: 300)
        host.view.frame = CGRect(origin: .zero, size: containerSize)
        host.view.layoutIfNeeded()

        let snackbarFrame = findFrame(
            in: host.view,
            accessibilityIdentifier: "snackbar_content"
        )
        let fabFrame = findFrame(
            in: host.view,
            accessibilityIdentifier: "fab_content"
        )

        guard let snackbarFrame, let fabFrame else {
            Issue.record("Could not find snackbar or FAB frames")
            return
        }

        #expect(
            !snackbarFrame.intersects(fabFrame),
            "Snackbar frame \(snackbarFrame) intersects FAB frame \(fabFrame)"
        )

        #expect(
            fabFrame.maxY <= snackbarFrame.minY + 1,
            "FAB bottom (\(fabFrame.maxY)) must be at or above snackbar top (\(snackbarFrame.minY))"
        )
    }

    // MARK: - Test 2: snackbar within safe area (non-zero inset)

    /// Uses `additionalSafeAreaInsets` to simulate a real home-indicator
    /// region (34pt). The snackbar must render entirely above the unsafe zone.
    @MainActor
    @Test("Bottom snackbar does not invade home indicator region")
    func bottomSnackbarWithinSafeArea() {
        let layout = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: .rest,
            undoContent: { undoPlaceholder },
            restContent: { snackbarPlaceholder },
            fab: { fabPlaceholder }
        )
        let host = UIHostingController(rootView: layout)
        // Simulate iPhone with 34pt bottom safe area (home indicator)
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 0)

        // Place inside a window to get proper safe area propagation
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 400))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()

        let snackbarFrame = findFrame(
            in: host.view,
            accessibilityIdentifier: "snackbar_content"
        )

        guard let snackbarFrame else {
            Issue.record("Could not find snackbar frame")
            window.isHidden = true
            return
        }

        // The safe area is the container height minus bottom inset.
        // snackbar must fit entirely within safe region (above the 34pt zone).
        let safeAreaBottom = host.view.bounds.height - host.view.safeAreaInsets.bottom
        #expect(
            snackbarFrame.maxY <= safeAreaBottom + 1,
            "Snackbar bottom (\(snackbarFrame.maxY)) extends into home indicator region (safe area ends at \(safeAreaBottom))"
        )

        window.isHidden = true
    }

    // MARK: - Test 3: top snackbar does not cover info band

    @MainActor
    @Test("Top snackbar does not overlap compact info band")
    func topSnackbarDoesNotCoverInfoBand() {
        let layout = ActiveWorkoutSnackbarLayout.topLayout(
            snackbarSlot: .rest,
            infoBand: { infoBandPlaceholder },
            snackbar: { snackbarPlaceholder }
        )
        let host = UIHostingController(rootView: layout)
        let containerSize = CGSize(width: 393, height: 200)
        host.view.frame = CGRect(origin: .zero, size: containerSize)
        host.view.layoutIfNeeded()

        let infoBandFrame = findFrame(
            in: host.view,
            accessibilityIdentifier: "info_band_content"
        )
        let snackbarFrame = findFrame(
            in: host.view,
            accessibilityIdentifier: "snackbar_content"
        )

        guard let infoBandFrame, let snackbarFrame else {
            Issue.record("Could not find info band or snackbar frames")
            return
        }

        #expect(
            !infoBandFrame.intersects(snackbarFrame),
            "Info band intersects snackbar; top snackbar must sit below the info band"
        )

        #expect(
            snackbarFrame.minY >= infoBandFrame.maxY - 1,
            "Snackbar top (\(snackbarFrame.minY)) must be at or below info band bottom (\(infoBandFrame.maxY))"
        )
    }

    // MARK: - Test 4: production rest timer buttons each >= 44pt in both dimensions

    /// Tests the actual production `ActiveWorkoutSnackbarLayout.restTimerButtons`
    /// helper (the same code path production `ActiveWorkoutView` calls) and
    /// asserts each individual button has a hit target >= 44pt in BOTH dimensions.
    @MainActor
    @Test("Each rest timer button (-10s, +10s, Skip) has >=44×44pt hit target")
    func restTimerButtonsHitTargets() {
        let content = ActiveWorkoutSnackbarLayout.restTimerButtons(skipTitle: "跳过")
        let host = UIHostingController(rootView: content)
        host.view.frame = CGRect(x: 0, y: 0, width: 393, height: 100)
        host.view.layoutIfNeeded()

        let buttonIds = ["rest_button_minus10", "rest_button_plus10", "rest_button_skip"]
        for buttonId in buttonIds {
            let frame = findFrame(in: host.view, accessibilityIdentifier: buttonId)
            guard let frame else {
                Issue.record("Could not find button '\(buttonId)'")
                continue
            }
            #expect(
                frame.height >= 44,
                "Button '\(buttonId)' height (\(frame.height)) must be >= 44pt"
            )
            #expect(
                frame.width >= 44,
                "Button '\(buttonId)' width (\(frame.width)) must be >= 44pt"
            )
        }
    }

    // MARK: - Test 5: No-list-jump — bottomSafeAreaContent height is constant (production content)

    /// MY-1446 P0-1 regression: the production `bottomSafeAreaContent` uses a
    /// ZStack envelope with both undo and rest content always laid out.
    /// This test verifies the height is constant across all slot states using
    /// real production-representative content:
    /// - undo: ZStack with hidden sizing reference + real multiline message
    /// - rest: completed banner + resting progress + buttons
    /// Tests at both default and large Dynamic Type sizes.
    @MainActor
    @Test("bottomSafeAreaContent height is constant across all slot states (no-list-jump)")
    func bottomSafeAreaContentHeightConstant() {
        let sizeCategories: [UIContentSizeCategory] = [.medium, .accessibilityExtraLarge]

        for sizeCategory in sizeCategories {
            // Measure each slot's height independently (BottomSnackbarSlot is not Hashable)
            let noneHeight = measureSlotHeight(slot: .none, sizeCategory: sizeCategory)
            let undoHeight = measureSlotHeight(slot: .undo, sizeCategory: sizeCategory)
            let restHeight = measureSlotHeight(slot: .rest, sizeCategory: sizeCategory)

            let tolerance: CGFloat = 1

            #expect(
                abs(noneHeight - undoHeight) <= tolerance,
                "[\(sizeCategory.rawValue)] Height shifted by \(abs(noneHeight - undoHeight))pt between .none (\(noneHeight)) and .undo (\(undoHeight)); must be within \(tolerance)pt"
            )
            #expect(
                abs(noneHeight - restHeight) <= tolerance,
                "[\(sizeCategory.rawValue)] Height shifted by \(abs(noneHeight - restHeight))pt between .none (\(noneHeight)) and .rest (\(restHeight)); must be within \(tolerance)pt"
            )
            #expect(
                abs(undoHeight - restHeight) <= tolerance,
                "[\(sizeCategory.rawValue)] Height shifted by \(abs(undoHeight - restHeight))pt between .undo (\(undoHeight)) and .rest (\(restHeight)); must be within \(tolerance)pt"
            )
        }
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

        let size = host.sizeThatFits(in: CGSize(width: 393, height: CGFloat.infinity))

        // Clean up
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()

        return size.height
    }

    // MARK: - Helpers

    /// Production-representative undo content. Uses the actual production
    /// `ActiveWorkoutSnackbarLayout.undoEnvelope` helper — the same code path
    /// that `ActiveWorkoutView.undoSnackbarEnvelope` calls. This ensures tests
    /// exercise the delivered code and will catch any drift.
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
    private var snackbarPlaceholder: some View {
        productionRestContent(completed: false)
            .accessibilityIdentifier("snackbar_content")
    }

    @MainActor
    private var fabPlaceholder: some View {
        Circle()
            .fill(Color.green.opacity(0.3))
            .frame(width: 60, height: 60)
            .padding()
            .accessibilityIdentifier("fab_content")
    }

    @MainActor
    private var infoBandPlaceholder: some View {
        Color.gray.opacity(0.3)
            .frame(height: 48)
            .accessibilityIdentifier("info_band_content")
    }

    /// Recursively searches for a UIView with the given accessibility identifier
    /// and returns its frame in the root view's coordinate space.
    @MainActor
    private func findFrame(
        in root: UIView,
        accessibilityIdentifier: String
    ) -> CGRect? {
        if root.accessibilityIdentifier == accessibilityIdentifier {
            return root.superview?.convert(root.frame, to: nil) ?? root.frame
        }
        for subview in root.subviews {
            if let found = findFrame(in: subview, accessibilityIdentifier: accessibilityIdentifier) {
                return found
            }
        }
        return nil
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
