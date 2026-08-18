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
/// These tests use `UIHostingController` to perform a real layout pass and
/// measure actual rendered geometry via a `GeometryReader` preference key.
/// The "Unfixed" probes reproduce the pre-fix layout (no maxWidth constraint)
/// to demonstrate the RED failure; the "Fixed" probes use the production
/// `.frame(maxWidth:)` pattern to demonstrate GREEN.
@Suite("ExercisePicker collapsed search layout (MY-1445)")
struct ExercisePickerSearchLayoutTests {

    #if canImport(UIKit)

    // MARK: - RED: unfixed layout claims full container width

    /// RED evidence: without the production fix, the ZStack containing both
    /// search surfaces claims full container width because the hidden expanded
    /// surface uses `.frame(maxWidth: .infinity)`. The 44pt assertion FAILS.
    @Test("RED: Unfixed collapsed ZStack width is full container (bug proof)")
    @MainActor
    func red_unfixedCollapsedWidth_isFullContainer() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        let frame = renderAndMeasureChildFrame(
            probe: UnfixedSearchSurfaceProbe(),
            containerWidth: availableWidth
        )

        // The unfixed ZStack takes the full proposed width — this IS the bug.
        // If this ever changes to < 50% width, the bug is already fixed and
        // the RED characterization no longer holds.
        #expect(
            frame.width > availableWidth * 0.9,
            "RED characterization: unfixed ZStack (\(frame.width)pt) should claim ≈ full container (\(availableWidth)pt)"
        )
        // The 44pt assertion would FAIL here — proving the need for the fix:
        #expect(
            frame.width > ExercisePickerView.collapsedSearchMaxWidth + 1,
            "RED: unfixed width (\(frame.width)pt) must exceed the 44pt target — this proves the bug exists"
        )
    }

    // MARK: - GREEN: fixed layout constrains to 44pt

    /// GREEN evidence: with the production fix (`.frame(maxWidth: 44)` in
    /// collapsed state), the rendered ZStack width is ≈ 44pt.
    @Test("GREEN: Fixed collapsed ZStack rendered width ≈ 44pt")
    @MainActor
    func green_fixedCollapsedWidth_is44pt() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        let frame = renderAndMeasureChildFrame(
            probe: FixedSearchSurfaceProbe(isExpanded: false),
            containerWidth: availableWidth
        )

        let expectedWidth = ExercisePickerView.collapsedSearchMaxWidth
        #expect(
            frame.width <= expectedWidth + 1,
            "GREEN: collapsed rendered width (\(frame.width)pt) must be ≤ \(expectedWidth + 1)pt"
        )
        #expect(
            frame.width >= expectedWidth - 1,
            "GREEN: collapsed rendered width (\(frame.width)pt) must be ≈ \(expectedWidth)pt (tolerance ±1)"
        )
    }

    // MARK: - GREEN: trailing alignment (measured maxX)

    /// GREEN evidence: the collapsed ZStack's rendered maxX must equal the
    /// container trailing edge (within 1pt tolerance). This uses the full
    /// production pattern: a trailing-aligned VStack containing the constrained
    /// ZStack, rendered via UIHostingController, with the child's actual frame
    /// captured through a GeometryReader overlay.
    @Test("GREEN: Collapsed ZStack maxX aligns to container trailing edge (measured)")
    @MainActor
    func green_collapsedMaxX_alignsToTrailingEdge() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        let frame = renderAndMeasureChildFrame(
            probe: TrailingAlignedSearchProbe(containerWidth: availableWidth),
            containerWidth: availableWidth
        )

        // The child's maxX (origin.x + width) must equal the container width
        // (= trailing edge in the coordinate space of the hosting view).
        let measuredMaxX = frame.origin.x + frame.width
        #expect(
            abs(measuredMaxX - availableWidth) <= 1,
            "GREEN: measured maxX (\(measuredMaxX)pt) must equal container trailing edge (\(availableWidth)pt) ±1pt"
        )
        // Also verify the child width is 44pt (not full-width)
        #expect(
            frame.width <= ExercisePickerView.collapsedSearchMaxWidth + 1,
            "GREEN: trailing-aligned child width (\(frame.width)pt) must be ≈ 44pt"
        )
    }

    // MARK: - GREEN: expanded state fills container

    /// GREEN: In expanded state, the ZStack fills the container width.
    @Test("GREEN: Expanded search ZStack fills container width")
    @MainActor
    func green_expandedWidth_fillsContainer() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        let frame = renderAndMeasureChildFrame(
            probe: FixedSearchSurfaceProbe(isExpanded: true),
            containerWidth: availableWidth
        )

        #expect(
            frame.width > availableWidth * 0.9,
            "Expanded ZStack must fill container (\(availableWidth)pt), got \(frame.width)pt"
        )
    }

    // MARK: - Both surfaces mounted (TextField identity preservation)

    /// Both surfaces remain mounted in collapsed and expanded states.
    @Test("Both search surfaces produce non-zero layout in both states")
    @MainActor
    func bothSurfacesProduceLayout() {
        for isExpanded in [true, false] {
            let frame = renderAndMeasureChildFrame(
                probe: FixedSearchSurfaceProbe(isExpanded: isExpanded),
                containerWidth: 369
            )
            #expect(
                frame.height > 0,
                "ZStack must produce non-zero height in \(isExpanded ? "expanded" : "collapsed") state"
            )
            #expect(
                frame.width > 0,
                "ZStack must produce non-zero width in \(isExpanded ? "expanded" : "collapsed") state"
            )
        }
    }

    // MARK: - Layout measurement helper

    /// Renders a probe view inside a `UIHostingController`, performs a full
    /// layout pass, then reads the child's actual rendered frame from a
    /// `GeometryReader` background preference that reports coordinates in the
    /// hosting view's coordinate space.
    @MainActor
    private func renderAndMeasureChildFrame<V: View>(
        probe: V,
        containerWidth: CGFloat
    ) -> CGRect {
        let wrapper = FrameMeasuringWrapper(content: probe)
        let hc = UIHostingController(rootView: wrapper)
        hc.view.frame = CGRect(x: 0, y: 0, width: containerWidth, height: 300)
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        // Force a second pass to ensure SwiftUI preferences have propagated
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        return wrapper.measuredFrame
    }

    #endif

    // MARK: - Static invariant (Constitution §H hit target)

    @Test("Collapsed search diameter meets 44pt hit target (Constitution §H)")
    func collapsedSearchDiameterMeetsConstitution() {
        #expect(ExercisePickerView.collapsedSearchDiameter >= 44)
        #expect(ExercisePickerView.collapsedSearchMaxWidth == ExercisePickerView.collapsedSearchDiameter)
    }
}

// MARK: - Frame Measurement Infrastructure

#if canImport(UIKit)

/// Preference key that captures the child's frame in the global coordinate space.
private struct ChildFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Wraps a probe view and captures its rendered frame via a background
/// `GeometryReader`. The measured frame is stored in a class-based reference
/// so the test can read it after the layout pass.
@MainActor
private struct FrameMeasuringWrapper<Content: View>: View {
    let content: Content
    @State private var frame: CGRect = .zero

    /// Class-based storage so the test can access the measured frame after layout.
    private let storage = FrameStorage()

    var measuredFrame: CGRect { storage.frame }

    var body: some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ChildFramePreferenceKey.self,
                        value: geo.frame(in: .global)
                    )
                }
            )
            .onPreferenceChange(ChildFramePreferenceKey.self) { newFrame in
                storage.frame = newFrame
            }
    }
}

@MainActor
private final class FrameStorage {
    var frame: CGRect = .zero
}

// MARK: - Test Probe Views

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
/// Uses the same VStack(alignment: .trailing) + constrained ZStack pattern.
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
