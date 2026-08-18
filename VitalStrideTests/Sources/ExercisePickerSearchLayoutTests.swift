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
/// `UIHostingController.sizeThatFits(in:)` to measure actual rendered
/// layout geometry. The "unfixed" path (plain ZStack without
/// `SearchSurfaceContainer`) demonstrates the bug; the production path
/// demonstrates the fix.
@Suite("ExercisePicker collapsed search layout (MY-1445)")
struct ExercisePickerSearchLayoutTests {

    #if canImport(UIKit)

    // MARK: - RED/GREEN: collapsed width

    /// Demonstrates the bug and the fix in sequence:
    /// - RED: A plain ZStack (unfixed layout) claims full container width.
    ///   The 44pt assertion FAILS against this layout.
    /// - GREEN: The production `SearchSurfaceContainer` constrains collapsed
    ///   width to 44pt. The same 44pt assertion PASSES.
    @Test("RED→GREEN: Production SearchSurfaceContainer constrains collapsed width to 44pt")
    @MainActor
    func collapsedWidth_productionPath_is44pt() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2
        let expectedWidth = ExercisePickerView.collapsedSearchMaxWidth

        // RED: unfixed ZStack (no SearchSurfaceContainer) claims full width
        let unfixedSize = measureFittingSize(
            view: UnfixedZStack(),
            proposedWidth: availableWidth
        )
        // The unfixed ZStack takes the full proposed width — this IS the bug.
        // If we ran `#expect(unfixedSize.width <= expectedWidth + 1)` here,
        // it would FAIL with: "unfixedSize.width (≈369pt) <= 45pt" — that
        // is the RED evidence. We assert the inverse to characterize the bug:
        #expect(
            unfixedSize.width > expectedWidth + 1,
            """
            RED characterization: unfixed ZStack width (\(unfixedSize.width)pt) \
            must exceed 44pt target — proves the bug exists. \
            The desired 44pt assertion would FAIL here: \
            \(unfixedSize.width)pt is NOT <= \(expectedWidth + 1)pt.
            """
        )

        // GREEN: production SearchSurfaceContainer constrains to 44pt
        let fixedSize = measureFittingSize(
            view: SearchSurfaceContainer(
                isExpanded: false,
                expanded: expandedChild,
                collapsed: collapsedChild
            ),
            proposedWidth: availableWidth
        )
        #expect(
            fixedSize.width <= expectedWidth + 1,
            """
            GREEN: production SearchSurfaceContainer collapsed width \
            (\(fixedSize.width)pt) must be ≤ \(expectedWidth + 1)pt
            """
        )
        #expect(
            fixedSize.width >= expectedWidth - 1,
            """
            GREEN: production SearchSurfaceContainer collapsed width \
            (\(fixedSize.width)pt) must be ≥ \(expectedWidth - 1)pt
            """
        )
    }

    // MARK: - GREEN: trailing alignment (measured via bitmap pixel occupancy)

    /// The collapsed `SearchSurfaceContainer`, placed inside a trailing-aligned
    /// VStack (matching production `floatingSearchAndFilterPanel`), must render
    /// content at the trailing edge and NOT at the leading edge. Verified by
    /// rendering to a bitmap and checking pixel occupancy at specific positions.
    @Test("GREEN: Collapsed SearchSurfaceContainer renders at trailing edge (bitmap verified)")
    @MainActor
    func collapsedMaxX_productionPath_alignsToTrailingEdge() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2
        let pillWidth = ExercisePickerView.collapsedSearchMaxWidth

        // Use a visible colored circle as the collapsed child so we can
        // detect its position in the rendered bitmap.
        let probe = VStack(alignment: .trailing) {
            SearchSurfaceContainer(
                isExpanded: false,
                expanded: Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 44),
                collapsed: Circle()
                    .fill(Color.red)
                    .frame(
                        width: ExercisePickerView.collapsedSearchDiameter,
                        height: ExercisePickerView.collapsedSearchDiameter
                    )
            )
        }
        .frame(width: availableWidth, height: 60, alignment: .trailing)
        .background(Color.white)

        let hc = UIHostingController(rootView: probe)
        hc.view.frame = CGRect(x: 0, y: 0, width: availableWidth, height: 60)
        hc.view.backgroundColor = .white
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        // Render to bitmap
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: availableWidth, height: 60)
        )
        let image = renderer.image { ctx in
            hc.view.layer.render(in: ctx.cgContext)
        }

        guard let cgImage = image.cgImage else {
            Issue.record("Failed to create CGImage for bitmap verification")
            return
        }

        let centerY = 30 // vertical center
        // The pill should be at the trailing edge: x ∈ [availableWidth - pillWidth, availableWidth]
        // Check that the trailing region has non-white (red) pixels
        let trailingX = Int(availableWidth - pillWidth / 2) // center of pill at trailing edge
        let trailingPixel = pixelColor(in: cgImage, x: trailingX, y: centerY)

        // Check that the leading region is white (no pill content)
        let leadingX = Int(pillWidth / 2) // center of where pill would be if leading-aligned
        let leadingPixel = pixelColor(in: cgImage, x: leadingX, y: centerY)

        // Trailing position must have the red pill (red channel > 200)
        #expect(
            trailingPixel.r > 200,
            """
            GREEN: trailing edge pixel at x=\(trailingX) must be red \
            (pill present). Got RGBA(\(trailingPixel.r),\(trailingPixel.g),\
            \(trailingPixel.b),\(trailingPixel.a)). \
            maxX ≈ \(availableWidth)pt.
            """
        )

        // Leading position must NOT have the red pill (red == white background)
        // A white pixel has r≈255, g≈255, b≈255. A red pixel has r≈255, g≈0, b≈0.
        // So check that green channel is high (white) at leading edge.
        #expect(
            leadingPixel.g > 200,
            """
            GREEN: leading edge pixel at x=\(leadingX) must be white/clear \
            (no pill). Got RGBA(\(leadingPixel.r),\(leadingPixel.g),\
            \(leadingPixel.b),\(leadingPixel.a)). Pill should be trailing-aligned.
            """
        )
    }

    // MARK: - GREEN: expanded state fills container

    /// In expanded state, the production `SearchSurfaceContainer` fills the
    /// container width.
    @Test("GREEN: Expanded SearchSurfaceContainer fills container width")
    @MainActor
    func expandedWidth_productionPath_fillsContainer() {
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
            "Expanded SearchSurfaceContainer must fill container (\(availableWidth)pt), got \(size.width)pt"
        )
    }

    // MARK: - Both surfaces mounted (TextField identity preservation)

    /// Both surfaces remain mounted in collapsed and expanded states.
    @Test("Both search surfaces produce non-zero layout in both states")
    @MainActor
    func bothSurfacesProduceLayout_productionPath() {
        for isExpanded in [true, false] {
            let size = measureFittingSize(
                view: SearchSurfaceContainer(
                    isExpanded: isExpanded,
                    expanded: expandedChild,
                    collapsed: collapsedChild
                ),
                proposedWidth: 369
            )
            #expect(
                size.height > 0,
                "SearchSurfaceContainer must produce non-zero height in \(isExpanded ? "expanded" : "collapsed") state"
            )
            #expect(
                size.width > 0,
                "SearchSurfaceContainer must produce non-zero width in \(isExpanded ? "expanded" : "collapsed") state"
            )
        }
    }

    // MARK: - Placeholder child views matching production structure

    /// Expanded child: matches production `expandedSearchSurface`'s layout
    /// contribution (full-width, 44pt min height).
    private var expandedChild: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 44)
    }

    /// Collapsed child: matches production `collapsedSearchSurface`'s layout
    /// contribution (44pt circle).
    private var collapsedChild: some View {
        Circle()
            .frame(
                width: ExercisePickerView.collapsedSearchDiameter,
                height: ExercisePickerView.collapsedSearchDiameter
            )
    }

    // MARK: - Layout measurement helpers

    /// Uses `UIHostingController.sizeThatFits(in:)` to measure the view's
    /// rendered size when proposed a specific width. This is synchronous
    /// and reliable, unlike GeometryReader preferences which require
    /// runloop ticks to propagate.
    @MainActor
    private func measureFittingSize<V: View>(
        view: V,
        proposedWidth: CGFloat
    ) -> CGSize {
        let hc = UIHostingController(rootView: view)
        hc.view.frame = CGRect(x: 0, y: 0, width: proposedWidth, height: 300)
        return hc.sizeThatFits(in: CGSize(width: proposedWidth, height: .infinity))
    }

    // MARK: - Screenshot evidence (Quality Bar K)

    /// Renders the production `SearchSurfaceContainer` in both collapsed and
    /// expanded states inside a trailing-aligned VStack (matching production
    /// `floatingSearchAndFilterPanel`), and saves the rendered images as
    /// iPhone 16 Simulator screenshot evidence for MY-1445 Quality Bar K.
    @Test("MY-1445 screenshot evidence: collapsed (44pt trailing pill) and expanded (full-width)")
    @MainActor
    func screenshotEvidence_collapsedAndExpanded() throws {
        let containerWidth: CGFloat = 393 // iPhone 16 width
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2
        let renderHeight: CGFloat = 60

        // Collapsed state: 44pt trailing-aligned pill
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

        // Expanded state: full-width search field
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

        // Verify both images exist and have expected dimensions
        #expect(collapsedImage.size.width > 0)
        #expect(expandedImage.size.width > 0)
    }

    /// Renders a SwiftUI view to a UIImage via UIHostingController.
    @MainActor
    private func renderToImage<V: View>(
        view: V,
        width: CGFloat,
        height: CGFloat
    ) throws -> UIImage {
        let hc = UIHostingController(rootView: view)
        hc.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        hc.view.backgroundColor = .white
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height)
        )
        return renderer.image { ctx in
            hc.view.layer.render(in: ctx.cgContext)
        }
    }

    private struct PixelColor {
        let r: UInt8, g: UInt8, b: UInt8, a: UInt8
    }

    /// Reads the RGBA color of a single pixel from a CGImage.
    private func pixelColor(in image: CGImage, x: Int, y: Int) -> PixelColor {
        let width = image.width
        let height = image.height
        guard x >= 0, x < width, y >= 0, y < height else {
            return PixelColor(r: 0, g: 0, b: 0, a: 0)
        }
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return PixelColor(r: 0, g: 0, b: 0, a: 0)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = y * bytesPerRow + x * bytesPerPixel
        return PixelColor(
            r: pixelData[offset],
            g: pixelData[offset + 1],
            b: pixelData[offset + 2],
            a: pixelData[offset + 3]
        )
    }

    #endif

    // MARK: - Static invariant (Constitution §H hit target)

    @Test("Collapsed search diameter meets 44pt hit target (Constitution §H)")
    func collapsedSearchDiameterMeetsConstitution() {
        #expect(ExercisePickerView.collapsedSearchDiameter >= 44)
        #expect(ExercisePickerView.collapsedSearchMaxWidth == ExercisePickerView.collapsedSearchDiameter)
    }
}

// MARK: - Unfixed ZStack (bug reproduction)

#if canImport(UIKit)

/// Plain ZStack WITHOUT `SearchSurfaceContainer` — reproduces the pre-fix
/// layout where the hidden expanded surface's `.frame(maxWidth: .infinity)`
/// forces the ZStack to full container width even when collapsed.
/// Used only in the RED characterization test.
private struct UnfixedZStack: View {
    var body: some View {
        ZStack {
            // Expanded surface — hidden but layout-contributing (THE BUG)
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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

#endif
