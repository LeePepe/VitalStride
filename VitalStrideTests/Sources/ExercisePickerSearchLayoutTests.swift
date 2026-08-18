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
/// These tests host the PRODUCTION `SearchSurfaceContainer` via
/// `UIHostingController` to measure actual rendered layout geometry.
@Suite("ExercisePicker collapsed search layout (MY-1445)")
struct ExercisePickerSearchLayoutTests {

    #if canImport(UIKit)

    // MARK: - Collapsed width must be 44pt

    /// The production `SearchSurfaceContainer` in collapsed state must render
    /// at approximately 44pt width — not the full container width. This is the
    /// core regression assertion for MY-1445.
    @Test("Collapsed SearchSurfaceContainer width is approximately 44pt")
    @MainActor
    func collapsedWidth_is44pt() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2
        let expectedWidth = ExercisePickerView.collapsedSearchMaxWidth

        let size = measureFittingSize(
            view: SearchSurfaceContainer(
                isExpanded: false,
                expanded: expandedChild,
                collapsed: collapsedChild
            ),
            proposedWidth: availableWidth
        )

        #expect(
            size.width <= expectedWidth + 1,
            "Collapsed width (\(size.width)pt) must be ≤ \(expectedWidth + 1)pt"
        )
        #expect(
            size.width >= expectedWidth - 1,
            "Collapsed width (\(size.width)pt) must be ≥ \(expectedWidth - 1)pt"
        )
    }

    // MARK: - Trailing alignment (geometry-verified)

    /// The collapsed `SearchSurfaceContainer`, placed inside a trailing-aligned
    /// frame (matching production `floatingSearchAndFilterPanel`), must position
    /// its content at the trailing edge. Verified by measuring the collapsed
    /// content's frame via a GeometryReader in a named coordinate space.
    @Test("Collapsed SearchSurfaceContainer renders at trailing edge (geometry verified)")
    @MainActor
    func collapsedMaxX_alignsToTrailingEdge() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        let frame = measureCollapsedFrame(alignment: .trailing, availableWidth: availableWidth)

        // The collapsed pill's maxX must align to the container's trailing edge
        #expect(
            abs(frame.maxX - availableWidth) <= 1,
            """
            Collapsed pill maxX (\(frame.maxX)pt) must align to trailing edge \
            (\(availableWidth)pt). Delta: \(abs(frame.maxX - availableWidth))pt.
            """
        )

        // The collapsed pill's width must be approximately 44pt
        #expect(
            abs(frame.width - ExercisePickerView.collapsedSearchMaxWidth) <= 1,
            """
            Collapsed pill width (\(frame.width)pt) must be approximately \
            \(ExercisePickerView.collapsedSearchMaxWidth)pt.
            """
        )
    }

    /// Proves the geometry test is not a false positive: when the container uses
    /// leading alignment, the collapsed pill appears at the leading edge instead.
    @Test("Leading-aligned container renders pill at leading edge (geometry control)")
    @MainActor
    func leadingAligned_pillAtLeadingEdge() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        let frame = measureCollapsedFrame(alignment: .leading, availableWidth: availableWidth)

        // The collapsed pill's minX must align to the container's leading edge
        #expect(
            abs(frame.minX) <= 1,
            """
            Collapsed pill minX (\(frame.minX)pt) must align to leading edge (0pt). \
            Delta: \(abs(frame.minX))pt.
            """
        )

        // The collapsed pill's width must be approximately 44pt
        #expect(
            abs(frame.width - ExercisePickerView.collapsedSearchMaxWidth) <= 1,
            """
            Collapsed pill width (\(frame.width)pt) must be approximately \
            \(ExercisePickerView.collapsedSearchMaxWidth)pt.
            """
        )
    }

    // MARK: - Expanded state fills container

    @Test("Expanded SearchSurfaceContainer fills container width")
    @MainActor
    func expandedWidth_fillsContainer() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2

        let size = measureFittingSize(
            view: SearchSurfaceContainer(
                isExpanded: true,
                expanded: expandedChild,
                collapsed: collapsedChild
            ),
            proposedWidth: availableWidth
        )

        #expect(
            size.width > availableWidth * 0.9,
            "Expanded width (\(size.width)pt) must fill container (\(availableWidth)pt)"
        )
    }

    // MARK: - Both surfaces mounted (TextField identity preservation)

    @Test("Both search surfaces produce non-zero layout in both states")
    @MainActor
    func bothSurfacesProduceLayout() {
        for isExpanded in [true, false] {
            let size = measureFittingSize(
                view: SearchSurfaceContainer(
                    isExpanded: isExpanded,
                    expanded: expandedChild,
                    collapsed: collapsedChild
                ),
                proposedWidth: 369
            )
            #expect(size.height > 0, "\(isExpanded ? "Expanded" : "Collapsed") must have non-zero height")
            #expect(size.width > 0, "\(isExpanded ? "Expanded" : "Collapsed") must have non-zero width")
        }
    }

    // MARK: - Child views matching production structure

    private var expandedChild: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 44)
    }

    private var collapsedChild: some View {
        Circle()
            .frame(
                width: ExercisePickerView.collapsedSearchDiameter,
                height: ExercisePickerView.collapsedSearchDiameter
            )
    }

    // MARK: - Layout measurement helpers

    @MainActor
    private func measureFittingSize<V: View>(
        view: V,
        proposedWidth: CGFloat
    ) -> CGSize {
        let hc = UIHostingController(rootView: view)
        hc.view.frame = CGRect(x: 0, y: 0, width: proposedWidth, height: 300)
        return hc.sizeThatFits(in: CGSize(width: proposedWidth, height: .infinity))
    }

    // MARK: - Geometry-based alignment measurement

    /// Measures the collapsed `SearchSurfaceContainer`'s frame within a container
    /// that applies the given horizontal alignment. Uses a GeometryReader in a
    /// named coordinate space to deterministically report the content's position
    /// after SwiftUI layout completes — no bitmap rendering required.
    @MainActor
    private func measureCollapsedFrame(
        alignment: HorizontalAlignment,
        availableWidth: CGFloat
    ) -> CGRect {
        let renderHeight: CGFloat = 60
        let capture = FrameCapture()
        let pillWidth = ExercisePickerView.collapsedSearchDiameter

        let probe = AlignmentProbeView(
            alignment: alignment,
            availableWidth: availableWidth,
            renderHeight: renderHeight,
            pillWidth: pillWidth,
            capture: capture
        )

        let hc = UIHostingController(rootView: probe)
        hc.view.frame = CGRect(x: 0, y: 0, width: availableWidth, height: renderHeight)

        // Attach to a UIWindow so SwiftUI fully resolves layout in headless CI
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: availableWidth, height: renderHeight))
        window.rootViewController = hc
        window.isHidden = false
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        // Allow SwiftUI's layout pass and preference propagation to complete
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        // Second tick to ensure onPreferenceChange fires
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        // Detach from window
        window.rootViewController = nil

        return capture.frame
    }

    // MARK: - Screenshot evidence (Quality Bar K)

    @Test("MY-1445 screenshot evidence: collapsed and expanded rendered states")
    @MainActor
    func screenshotEvidence_collapsedAndExpanded() throws {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2
        let renderHeight: CGFloat = 60

        let collapsedImage = try renderToImage(
            view: VStack(alignment: .trailing) {
                SearchSurfaceContainer(
                    isExpanded: false,
                    expanded: Color.blue.opacity(0.2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44),
                    collapsed: Circle()
                        .fill(Color.blue)
                        .frame(
                            width: ExercisePickerView.collapsedSearchDiameter,
                            height: ExercisePickerView.collapsedSearchDiameter
                        )
                )
            }
            .frame(width: availableWidth, height: renderHeight, alignment: .trailing)
            .background(Color.white),
            width: availableWidth,
            height: renderHeight
        )

        let collapsedPath = "/tmp/MY-1445_collapsed_search_iPhone16.png"
        try collapsedImage.pngData()?.write(to: URL(fileURLWithPath: collapsedPath))

        let expandedImage = try renderToImage(
            view: VStack(alignment: .trailing) {
                SearchSurfaceContainer(
                    isExpanded: true,
                    expanded: RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.15))
                        .overlay(
                            HStack {
                                Image(systemName: "magnifyingglass")
                                Text("bench")
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .foregroundStyle(.secondary)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 44),
                    collapsed: Circle()
                        .fill(Color.blue)
                        .frame(
                            width: ExercisePickerView.collapsedSearchDiameter,
                            height: ExercisePickerView.collapsedSearchDiameter
                        )
                )
            }
            .frame(width: availableWidth, height: renderHeight, alignment: .trailing)
            .background(Color.white),
            width: availableWidth,
            height: renderHeight
        )

        let expandedPath = "/tmp/MY-1445_expanded_search_iPhone16.png"
        try expandedImage.pngData()?.write(to: URL(fileURLWithPath: expandedPath))

        #expect(collapsedImage.size.width > 0)
        #expect(expandedImage.size.width > 0)
    }

    @MainActor
    private func renderToImage<V: View>(
        view: V,
        width: CGFloat,
        height: CGFloat
    ) throws -> UIImage {
        let hc = UIHostingController(rootView: view)
        hc.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        hc.view.backgroundColor = .white

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        window.rootViewController = hc
        window.isHidden = false
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let result = renderer.image { ctx in
            hc.view.layer.render(in: ctx.cgContext)
        }
        window.rootViewController = nil
        return result
    }

    #endif

    // MARK: - Static invariant (Constitution §H hit target)

    @Test("Collapsed search diameter meets 44pt hit target (Constitution §H)")
    func collapsedSearchDiameterMeetsConstitution() {
        #expect(ExercisePickerView.collapsedSearchDiameter >= 44)
        #expect(ExercisePickerView.collapsedSearchMaxWidth == ExercisePickerView.collapsedSearchDiameter)
    }
}

// MARK: - Geometry measurement support types

#if canImport(UIKit)

/// Captures a CGRect frame from a geometry measurement. Used as a reference
/// type so the test can read the value after SwiftUI layout completes.
@MainActor
private final class FrameCapture {
    var frame: CGRect = .zero
}

/// Preference key for propagating a measured frame up the view tree.
private struct CollapsedFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// A test-only probe view that places `SearchSurfaceContainer` in a container
/// with the given alignment, then uses a GeometryReader + preference key in a
/// named coordinate space to deterministically measure where the collapsed pill
/// renders — without relying on bitmap capture.
private struct AlignmentProbeView: View {
    let alignment: HorizontalAlignment
    let availableWidth: CGFloat
    let renderHeight: CGFloat
    let pillWidth: CGFloat
    let capture: FrameCapture

    var body: some View {
        VStack(alignment: alignment) {
            SearchSurfaceContainer(
                isExpanded: false,
                expanded: Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 44),
                collapsed: Circle()
                    .frame(width: pillWidth, height: pillWidth)
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: CollapsedFramePreferenceKey.self,
                                    value: geo.frame(in: .named("alignmentContainer"))
                                )
                        }
                    )
            )
        }
        .frame(
            width: availableWidth,
            height: renderHeight,
            alignment: Alignment(horizontal: alignment, vertical: .center)
        )
        .coordinateSpace(name: "alignmentContainer")
        .onPreferenceChange(CollapsedFramePreferenceKey.self) { frame in
            capture.frame = frame
        }
    }
}

#endif
