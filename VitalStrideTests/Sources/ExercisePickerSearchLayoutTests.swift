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
    /// rendering to a 1× bitmap and checking pixel occupancy at specific positions.
    @Test("Collapsed SearchSurfaceContainer renders at trailing edge (bitmap verified)")
    @MainActor
    func collapsedMaxX_alignsToTrailingEdge() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2
        let pillWidth = ExercisePickerView.collapsedSearchMaxWidth

        // Trailing-aligned (production layout) — pill must be at trailing edge
        let trailingResult = renderAndSamplePillPosition(
            alignment: .trailing,
            availableWidth: availableWidth,
            pillWidth: pillWidth
        )

        // Trailing position must have the red pill: high R, low G and B
        #expect(
            trailingResult.trailingPixel.r > 200 && trailingResult.trailingPixel.g < 50 && trailingResult.trailingPixel.b < 50,
            """
            Trailing edge pixel must be red (pill present). \
            Got RGBA(\(trailingResult.trailingPixel.r),\(trailingResult.trailingPixel.g),\(trailingResult.trailingPixel.b),\(trailingResult.trailingPixel.a)).
            """
        )

        // Leading position must be white (no pill): all channels > 200
        #expect(
            trailingResult.leadingPixel.r > 200 && trailingResult.leadingPixel.g > 200 && trailingResult.leadingPixel.b > 200,
            """
            Leading edge pixel must be white (no pill). \
            Got RGBA(\(trailingResult.leadingPixel.r),\(trailingResult.leadingPixel.g),\(trailingResult.leadingPixel.b),\(trailingResult.leadingPixel.a)).
            """
        )
    }

    /// Proves the bitmap test is not a false positive: when the VStack uses
    /// leading alignment, the red pill appears at the leading edge instead.
    @Test("Leading-aligned container renders pill at leading edge (bitmap control)")
    @MainActor
    func leadingAligned_pillAtLeadingEdge() {
        let containerWidth: CGFloat = 393
        let panelInset = ExercisePickerView.panelHorizontalInset
        let availableWidth = containerWidth - panelInset * 2
        let pillWidth = ExercisePickerView.collapsedSearchMaxWidth

        // Leading-aligned — pill must be at leading edge
        let leadingResult = renderAndSamplePillPosition(
            alignment: .leading,
            availableWidth: availableWidth,
            pillWidth: pillWidth
        )

        // Leading position must have the red pill
        #expect(
            leadingResult.leadingPixel.r > 200 && leadingResult.leadingPixel.g < 50 && leadingResult.leadingPixel.b < 50,
            """
            Leading edge pixel must be red (pill present in leading-aligned layout). \
            Got RGBA(\(leadingResult.leadingPixel.r),\(leadingResult.leadingPixel.g),\(leadingResult.leadingPixel.b),\(leadingResult.leadingPixel.a)).
            """
        )

        // Trailing position must be white (no pill)
        #expect(
            leadingResult.trailingPixel.r > 200 && leadingResult.trailingPixel.g > 200 && leadingResult.trailingPixel.b > 200,
            """
            Trailing edge pixel must be white (no pill in leading-aligned layout). \
            Got RGBA(\(leadingResult.trailingPixel.r),\(leadingResult.trailingPixel.g),\(leadingResult.trailingPixel.b),\(leadingResult.trailingPixel.a)).
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

    // MARK: - Bitmap alignment helpers

    private struct BitmapSample {
        let trailingPixel: PixelColor
        let leadingPixel: PixelColor
    }

    /// Renders the collapsed `SearchSurfaceContainer` inside a VStack with the
    /// given horizontal alignment, captures a 1× bitmap, and samples pixels at
    /// the pill center positions (leading and trailing edges).
    ///
    /// The hosting controller is added to a `UIWindow` to ensure SwiftUI fully
    /// resolves layout even in headless CI environments.
    @MainActor
    private func renderAndSamplePillPosition(
        alignment: HorizontalAlignment,
        availableWidth: CGFloat,
        pillWidth: CGFloat
    ) -> BitmapSample {
        let renderHeight: CGFloat = 60

        let probe = VStack(alignment: alignment) {
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
        .frame(width: availableWidth, height: renderHeight, alignment: Alignment(horizontal: alignment, vertical: .center))
        .background(Color.white)

        let hc = UIHostingController(rootView: probe)
        hc.view.frame = CGRect(x: 0, y: 0, width: availableWidth, height: renderHeight)
        hc.view.backgroundColor = .white

        // Attach to a UIWindow so SwiftUI resolves layout in headless CI
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: availableWidth, height: renderHeight))
        window.rootViewController = hc
        window.isHidden = false
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        // Ensure SwiftUI's async layout pass completes
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        // Use scale=1 so CGImage pixel coordinates match point coordinates
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: availableWidth, height: renderHeight),
            format: format
        )
        let image = renderer.image { ctx in
            hc.view.layer.render(in: ctx.cgContext)
        }

        // Detach from window
        window.rootViewController = nil

        guard let cgImage = image.cgImage else {
            return BitmapSample(
                trailingPixel: PixelColor(r: 0, g: 0, b: 0, a: 0),
                leadingPixel: PixelColor(r: 0, g: 0, b: 0, a: 0)
            )
        }

        let centerY = Int(renderHeight / 2)
        // Sample at pill center positions
        let trailingX = Int(availableWidth - pillWidth / 2)
        let leadingX = Int(pillWidth / 2)

        return BitmapSample(
            trailingPixel: pixelColor(in: cgImage, x: trailingX, y: centerY),
            leadingPixel: pixelColor(in: cgImage, x: leadingX, y: centerY)
        )
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

        // Attach to a UIWindow so SwiftUI resolves layout in headless CI
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
        let totalBytes = bytesPerRow * height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return PixelColor(r: 0, g: 0, b: 0, a: 0)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else {
            return PixelColor(r: 0, g: 0, b: 0, a: 0)
        }
        let buffer = data.assumingMemoryBound(to: UInt8.self)
        let offset = y * bytesPerRow + x * bytesPerPixel
        guard offset + 3 < totalBytes else {
            return PixelColor(r: 0, g: 0, b: 0, a: 0)
        }
        return PixelColor(
            r: buffer[offset],
            g: buffer[offset + 1],
            b: buffer[offset + 2],
            a: buffer[offset + 3]
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
