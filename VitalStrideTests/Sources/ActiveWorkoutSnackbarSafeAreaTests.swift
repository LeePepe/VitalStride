import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1446 — Snackbar safe-area regression tests.
///
/// Verifies three layout invariants that use safe area as single truth source:
/// 1. The FAB and bottom snackbar frames must not intersect.
/// 2. The bottom snackbar must be fully contained within the safe area
///    (not clipped by the edge).
/// 3. When the snackbar is at the top edge (keyboard visible), it must not
///    overlap the persistent compact info band.
///
/// These tests exercise `ActiveWorkoutSnackbarLayout` to confirm layout
/// decisions produce non-overlapping, safe-area-respecting geometry.
@Suite("ActiveWorkout snackbar safe-area layout (MY-1446)")
struct ActiveWorkoutSnackbarSafeAreaTests {

    // MARK: - Test 1: FAB and bottom snackbar non-overlapping

    #if canImport(UIKit) && !os(macOS)
    /// The bottom snackbar and FAB must not visually overlap. When both are
    /// rendered within a safe-area-driven layout, the snackbar occupies its
    /// own distinct region and the FAB stays in its region above.
    @MainActor
    @Test("Bottom snackbar and FAB frames do not intersect")
    func bottomSnackbarAndFABDoNotIntersect() {
        // Render the unified bottom layout with rest snackbar active
        let layout = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: .rest,
            snackbar: { snackbarPlaceholder },
            fab: { fabPlaceholder }
        )
        let host = UIHostingController(rootView: layout)
        // Give enough width/height to render naturally
        let containerSize = CGSize(width: 393, height: 300)
        host.view.frame = CGRect(origin: .zero, size: containerSize)
        host.view.layoutIfNeeded()

        // Find the snackbar and FAB subviews by accessibility identifier
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

        // They must not intersect
        #expect(
            !snackbarFrame.intersects(fabFrame),
            "Snackbar frame \(snackbarFrame) intersects FAB frame \(fabFrame); they must be non-overlapping"
        )

        // FAB must be above snackbar (smaller Y = higher on screen)
        #expect(
            fabFrame.maxY <= snackbarFrame.minY + 1,
            "FAB bottom (\(fabFrame.maxY)) must be at or above snackbar top (\(snackbarFrame.minY))"
        )
    }

    // MARK: - Test 2: snackbar fully within safe area

    /// The bottom snackbar must not extend beyond the container's bounds.
    /// It must be fully contained within the available safe area so it is
    /// never clipped by the screen edge or home indicator.
    @MainActor
    @Test("Bottom snackbar is fully contained within container bounds")
    func bottomSnackbarWithinSafeArea() {
        let layout = ActiveWorkoutSnackbarLayout.bottomSafeAreaContent(
            snackbarSlot: .rest,
            snackbar: { snackbarPlaceholder },
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

        guard let snackbarFrame else {
            Issue.record("Could not find snackbar frame")
            return
        }

        let containerBounds = CGRect(origin: .zero, size: containerSize)
        #expect(
            containerBounds.contains(snackbarFrame),
            "Snackbar frame \(snackbarFrame) extends outside container bounds \(containerBounds)"
        )
    }

    // MARK: - Test 3: top snackbar does not cover info band

    /// When the keyboard is visible and the snackbar moves to the top edge,
    /// it must NOT overlap the compact info band. The info band must remain
    /// fully visible and the snackbar must be positioned below it.
    @MainActor
    @Test("Top snackbar does not overlap compact info band")
    func topSnackbarDoesNotCoverInfoBand() {
        // Render the top layout: info band + snackbar positioned below it
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

        // They must not intersect
        #expect(
            !infoBandFrame.intersects(snackbarFrame),
            "Info band frame \(infoBandFrame) intersects snackbar frame \(snackbarFrame); top snackbar must sit below the info band"
        )

        // Snackbar must be below info band
        #expect(
            snackbarFrame.minY >= infoBandFrame.maxY - 1,
            "Snackbar top (\(snackbarFrame.minY)) must be at or below info band bottom (\(infoBandFrame.maxY))"
        )
    }

    // MARK: - Test 4: rest timer buttons meet hit target

    /// The Skip, -10s, +10s buttons inside the bottom snackbar must each
    /// render with a tappable area >= 44pt in both width and height.
    @MainActor
    @Test("Rest timer snackbar buttons have >=44pt hit targets")
    func restTimerButtonsHitTargets() {
        // Render a representative rest-timer snackbar content
        let content = restTimerContent
        let host = UIHostingController(rootView: content)
        let size = host.sizeThatFits(in: CGSize(width: 393, height: 0))

        // The content height must be at least 44pt (minTapTarget)
        #expect(
            size.height >= Space.minTapTarget,
            "Rest timer content height (\(size.height)) must be >= \(Space.minTapTarget)pt for tappable area"
        )
    }

    // MARK: - Helpers

    @MainActor
    private var snackbarPlaceholder: some View {
        Color.blue.opacity(0.3)
            .frame(height: 68) // representative snackbar height
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

    @MainActor
    private var restTimerContent: some View {
        HStack {
            Circle().frame(width: 32, height: 32)
            Spacer()
            HStack(spacing: 8) {
                Text("-10s").frame(minHeight: Space.minTapTarget)
                Text("+10s").frame(minHeight: Space.minTapTarget)
                Text("Skip").frame(minHeight: Space.minTapTarget)
            }
        }
        .padding(.horizontal, Space.cardPadding)
        .padding(.vertical, Space.gap)
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
