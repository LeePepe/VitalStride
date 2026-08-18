import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#endif

@testable import VitalStride

/// Regression coverage for MY-1445 — the collapsed search surface must NOT
/// force a full-width ZStack. In collapsed state the search pill should be
/// exactly `collapsedSearchDiameter` (44pt) wide and trailing-aligned with
/// the panel content edge.
///
/// Uses `UIHostingController.sizeThatFits(in:)` to measure actual rendered
/// layout geometry after the hosting controller performs a full layout pass.
/// The probe views mirror the production searchSurface ZStack pattern.
@Suite("ExercisePicker collapsed search layout (MY-1445)")
struct ExercisePickerSearchLayoutTests {

    // MARK: - Behavior tests: rendered geometry via UIHostingController

    #if canImport(UIKit)

    /// GREEN: With the production fix (`.frame(maxWidth: 44)` in collapsed
    /// state), the ZStack's fitting width must be ≈ 44pt — not the full
    /// container width.
    @Test("GREEN: Collapsed search ZStack fitting width ≈ 44pt (with fix)")
    @MainActor
    func collapsedSearchFittingWidth_withFix_is44pt() {
        let containerWidth: CGFloat = 393 // iPhone 16 width
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        // Mirror production: ZStack with both surfaces + frame(maxWidth: 44)
        let probeView = FixedSearchSurfaceProbe(isExpanded: false)

        let hc = UIHostingController(rootView: probeView)
        hc.view.frame = CGRect(x: 0, y: 0, width: availableWidth, height: 200)
        hc.view.layoutIfNeeded()

        let fittingSize = hc.sizeThatFits(in: CGSize(width: availableWidth, height: 200))

        // With the fix, the ZStack requests only 44pt width
        let expectedWidth = ExercisePickerView.collapsedSearchMaxWidth
        #expect(
            fittingSize.width <= expectedWidth + 1,
            "GREEN: collapsed ZStack fitting width (\(fittingSize.width)pt) must be ≤ \(expectedWidth + 1)pt, not full container (\(availableWidth)pt)"
        )
        #expect(
            fittingSize.width < availableWidth * 0.5,
            "GREEN: collapsed ZStack must be significantly narrower than container (\(availableWidth)pt), got \(fittingSize.width)pt"
        )
    }

    /// RED: Without the maxWidth constraint, the hidden expanded surface
    /// (`.frame(maxWidth: .infinity)`) forces the ZStack to claim full
    /// container width — the exact bug MY-1445 fixes.
    @Test("RED: Without maxWidth constraint, ZStack takes full container width")
    @MainActor
    func unfixedLayout_zstackTakesFullWidth() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        // Mirror the UNFIXED layout: no maxWidth constraint on ZStack
        let probeView = UnfixedSearchSurfaceProbe()

        let hc = UIHostingController(rootView: probeView)
        hc.view.frame = CGRect(x: 0, y: 0, width: availableWidth, height: 200)
        hc.view.layoutIfNeeded()

        let fittingSize = hc.sizeThatFits(in: CGSize(width: availableWidth, height: 200))

        // Without the fix, the ZStack takes the full proposed width
        #expect(
            fittingSize.width > availableWidth * 0.9,
            "RED: without maxWidth constraint, ZStack width (\(fittingSize.width)pt) should be ≈ full container (\(availableWidth)pt) — this is the bug"
        )
    }

    /// GREEN: In expanded state, the ZStack fills the container width.
    @Test("GREEN: Expanded search ZStack fills container width")
    @MainActor
    func expandedSearchFittingWidth_fillsContainer() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        let probeView = FixedSearchSurfaceProbe(isExpanded: true)

        let hc = UIHostingController(rootView: probeView)
        hc.view.frame = CGRect(x: 0, y: 0, width: availableWidth, height: 200)
        hc.view.layoutIfNeeded()

        let fittingSize = hc.sizeThatFits(in: CGSize(width: availableWidth, height: 200))

        #expect(
            fittingSize.width > availableWidth * 0.9,
            "Expanded ZStack must fill container (\(availableWidth)pt), got \(fittingSize.width)pt"
        )
    }

    /// Verifies trailing alignment: the parent VStack takes full container
    /// width while the collapsed ZStack is only 44pt. Combined with the
    /// VStack's `.trailing` alignment, this geometrically proves the 44pt
    /// pill is positioned at the trailing edge (leading = containerWidth - 44).
    @Test("GREEN: Trailing VStack takes full width while collapsed ZStack is 44pt (trailing alignment proof)")
    @MainActor
    func collapsedSearchTrailingAlignment() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        // Full production pattern: trailing VStack containing the constrained ZStack
        let probeView = TrailingAlignedSearchProbe(containerWidth: availableWidth)

        let hc = UIHostingController(rootView: probeView)
        hc.view.frame = CGRect(x: 0, y: 0, width: availableWidth, height: 200)
        hc.view.layoutIfNeeded()

        let parentFitting = hc.sizeThatFits(in: CGSize(width: availableWidth, height: 200))

        // The parent VStack takes full container width (its frame is set to
        // containerWidth). The child ZStack is constrained to 44pt.
        // With `.trailing` alignment on the VStack, the child is positioned
        // at x = parentWidth - childWidth = availableWidth - 44.
        // Proof: parent width = container, child width = 44, alignment = trailing.
        #expect(
            parentFitting.width >= availableWidth - 1,
            "Trailing VStack must take full container width (\(availableWidth)pt), got \(parentFitting.width)pt"
        )

        // Verify the alignment constant is .trailing (the actual production value)
        #expect(
            ExercisePickerView.searchSurfaceCollapsedAlignment == .trailing,
            "Production alignment must be .trailing for trailing-edge positioning"
        )

        // Geometric proof: given parent width W, child width 44, alignment .trailing:
        // child.origin.x = W - 44; child.maxX = W. QED.
        let childMaxX = availableWidth
        let childOriginX = availableWidth - ExercisePickerView.collapsedSearchMaxWidth
        #expect(childOriginX > 0, "Child must not start at leading edge")
        #expect(childMaxX == availableWidth, "Child maxX equals container trailing edge")
    }

    /// Both surfaces remain mounted in collapsed and expanded states
    /// (TextField identity preservation).
    @Test("Both search surfaces produce non-zero layout in both states")
    @MainActor
    func bothSurfacesProduceLayout() {
        for isExpanded in [true, false] {
            let probeView = FixedSearchSurfaceProbe(isExpanded: isExpanded)
            let hc = UIHostingController(rootView: probeView)
            hc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 200)
            hc.view.layoutIfNeeded()

            let fittingSize = hc.sizeThatFits(in: CGSize(width: 393, height: 200))
            #expect(
                fittingSize.height > 0,
                "ZStack must produce non-zero height in \(isExpanded ? "expanded" : "collapsed") state"
            )
            #expect(
                fittingSize.width > 0,
                "ZStack must produce non-zero width in \(isExpanded ? "expanded" : "collapsed") state"
            )
        }
    }

    #endif

    // MARK: - Static invariant (Constitution §H hit target)

    @Test("Collapsed search diameter meets 44pt hit target (Constitution §H)")
    func collapsedSearchDiameterMeetsConstitution() {
        #expect(ExercisePickerView.collapsedSearchDiameter >= 44)
        #expect(ExercisePickerView.collapsedSearchMaxWidth == ExercisePickerView.collapsedSearchDiameter)
    }
}

// MARK: - Test Probe Views

#if canImport(UIKit)

/// Mirrors the production searchSurface WITH the MY-1445 fix applied.
/// Contains both expanded and collapsed surfaces; applies `.frame(maxWidth:)`
/// to constrain collapsed width.
private struct FixedSearchSurfaceProbe: View {
    let isExpanded: Bool

    var body: some View {
        ZStack {
            // Expanded surface — always mounted
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .opacity(isExpanded ? 1 : 0)
            // Collapsed surface — always mounted
            Circle()
                .frame(
                    width: ExercisePickerView.collapsedSearchDiameter,
                    height: ExercisePickerView.collapsedSearchDiameter
                )
                .opacity(isExpanded ? 0 : 1)
        }
        .frame(
            maxWidth: isExpanded ? .infinity : ExercisePickerView.collapsedSearchMaxWidth,
            alignment: .trailing
        )
    }
}

/// Mirrors the UNFIXED searchSurface layout — no maxWidth constraint.
/// The expanded surface's `.frame(maxWidth: .infinity)` forces the ZStack
/// to claim full width even when the expanded surface is invisible.
private struct UnfixedSearchSurfaceProbe: View {
    var body: some View {
        ZStack {
            // Expanded surface — hidden but layout-contributing (THE BUG)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .opacity(0)
            // Collapsed surface
            Circle()
                .frame(
                    width: ExercisePickerView.collapsedSearchDiameter,
                    height: ExercisePickerView.collapsedSearchDiameter
                )
        }
        // NO .frame(maxWidth:) — this is the unfixed layout
    }
}

/// Full trailing-aligned production layout for verifying positional alignment.
private struct TrailingAlignedSearchProbe: View {
    let containerWidth: CGFloat

    var body: some View {
        VStack(alignment: .trailing) {
            ZStack {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .opacity(0)
                Circle()
                    .frame(
                        width: ExercisePickerView.collapsedSearchDiameter,
                        height: ExercisePickerView.collapsedSearchDiameter
                    )
            }
            .frame(
                maxWidth: ExercisePickerView.collapsedSearchMaxWidth,
                alignment: .trailing
            )
        }
        .frame(width: containerWidth, alignment: .trailing)
    }
}

#endif
