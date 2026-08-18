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

    // MARK: - Trailing alignment (bitmap-verified)

    /// The collapsed `SearchSurfaceContainer`, placed inside a trailing-aligned
    /// VStack (matching production `floatingSearchAndFilterPanel`), must render
    /// content at the trailing edge and NOT at the leading edge. Verified by
    /// rendering to a bitmap and checking pixel occupancy at specific positions.
    @Test("Collapsed SearchSurfaceContainer renders at trailing edge (bitmap verified)")
    @MainActor
    func collapsedMaxX_alignsToTrailingEdge() {
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

        let centerY = 30
        // The pill should be at the trailing edge: center of pill near availableWidth - pillWidth/2
        let trailingX = Int(availableWidth - pillWidth / 2)
        let trailingPixel = pixelColor(in: cgImage, x: trailingX, y: centerY)

        // Leading region should be white (no pill content)
        let leadingX = Int(pillWidth / 2)
        let leadingPixel = pixelColor(in: cgImage, x: leadingX, y: centerY)

        // Trailing position must have the red pill
        #expect(
            trailingPixel.r > 200,
            """
            Trailing edge pixel at x=\(trailingX) must be red (pill present). \
            Got RGBA(\(trailingPixel.r),\(trailingPixel.g),\(trailingPixel.b),\(trailingPixel.a)).
            """
        )

        // Leading position must NOT have the red pill (white background: g > 200)
        #expect(
            leadingPixel.g > 200,
            """
            Leading edge pixel at x=\(leadingX) must be white/clear (no pill). \
            Got RGBA(\(leadingPixel.r),\(leadingPixel.g),\(leadingPixel.b),\(leadingPixel.a)).
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
