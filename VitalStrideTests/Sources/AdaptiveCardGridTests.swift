import Foundation
import Testing
import AIService
#if canImport(UIKit)
import DesignKit
import SwiftUI
import UIKit
#endif

@testable import VitalStride

@Suite("GridLayoutEngine Tests")
struct GridLayoutEngineTests {

    // MARK: - Helpers

    private func makeInsight(
        key: String = "k",
        type: String = "metric",
        size: String = "small"
    ) -> OverviewInsight {
        OverviewInsight(
            key: key,
            cardType: type,
            cardSize: size,
            title: "T",
            content: "C"
        )
    }

    // MARK: - Segmentation

    @Test("Mixed sizes segment correctly: [small, small, wide, medium, large, small, small]")
    func mixedSizesSegmentation() {
        let insights = [
            makeInsight(key: "1", type: "metric", size: "small"),
            makeInsight(key: "2", type: "action", size: "small"),
            makeInsight(key: "3", type: "trend", size: "wide"),
            makeInsight(key: "4", type: "metric", size: "medium"),
            makeInsight(key: "5", type: "summary", size: "large"),
            makeInsight(key: "6", type: "metric", size: "small"),
            makeInsight(key: "7", type: "action", size: "small"),
        ]

        let (segments, filteredCount) = GridLayoutEngine.segment(insights)

        #expect(filteredCount == 0)
        #expect(segments.count == 5)

        if case let .gridBatch(batch) = segments[0] {
            #expect(batch.count == 2)
            #expect(batch[0].key == "1")
            #expect(batch[1].key == "2")
        } else {
            Issue.record("Expected gridBatch at index 0")
        }

        if case let .fullWidth(insight) = segments[1] {
            #expect(insight.key == "3")
        } else {
            Issue.record("Expected fullWidth at index 1")
        }

        if case let .gridBatch(batch) = segments[2] {
            #expect(batch.count == 1)
            #expect(batch[0].key == "4")
        } else {
            Issue.record("Expected gridBatch at index 2")
        }

        if case let .fullWidth(insight) = segments[3] {
            #expect(insight.key == "5")
        } else {
            Issue.record("Expected fullWidth at index 3")
        }

        if case let .gridBatch(batch) = segments[4] {
            #expect(batch.count == 2)
            #expect(batch[0].key == "6")
            #expect(batch[1].key == "7")
        } else {
            Issue.record("Expected gridBatch at index 4")
        }
    }

    @Test("All small/medium produces single grid batch")
    func allSmallMediumSingleBatch() {
        let insights = [
            makeInsight(key: "1", type: "metric", size: "small"),
            makeInsight(key: "2", type: "metric", size: "medium"),
            makeInsight(key: "3", type: "action", size: "small"),
        ]

        let (segments, filteredCount) = GridLayoutEngine.segment(insights)

        #expect(filteredCount == 0)
        #expect(segments.count == 1)

        if case let .gridBatch(batch) = segments[0] {
            #expect(batch.count == 3)
        } else {
            Issue.record("Expected single gridBatch")
        }
    }

    @Test("All wide/large produces only fullWidth segments")
    func allWideOrLargeFullWidth() {
        let insights = [
            makeInsight(key: "1", type: "trend", size: "wide"),
            makeInsight(key: "2", type: "summary", size: "large"),
            makeInsight(key: "3", type: "list", size: "wide"),
        ]

        let (segments, filteredCount) = GridLayoutEngine.segment(insights)

        #expect(filteredCount == 0)
        #expect(segments.count == 3)

        for segment in segments {
            if case .gridBatch = segment {
                Issue.record("Expected no gridBatch segments")
            }
        }
    }

    @Test("Empty input returns empty segments")
    func emptyInput() {
        let (segments, filteredCount) = GridLayoutEngine.segment([])

        #expect(segments.isEmpty)
        #expect(filteredCount == 0)
    }

    @Test("Preserves AI-given order within grid batches")
    func preservesOrder() {
        let insights = [
            makeInsight(key: "a", type: "metric", size: "small"),
            makeInsight(key: "b", type: "trend", size: "medium"),
            makeInsight(key: "c", type: "action", size: "small"),
        ]

        let (segments, _) = GridLayoutEngine.segment(insights)

        #expect(segments.count == 1)
        if case let .gridBatch(batch) = segments[0] {
            #expect(batch.map(\.key) == ["a", "b", "c"])
        } else {
            Issue.record("Expected gridBatch")
        }
    }

    @Test("Consecutive wide/large each get their own fullWidth segment")
    func consecutiveFullWidth() {
        let insights = [
            makeInsight(key: "1", type: "trend", size: "wide"),
            makeInsight(key: "2", type: "summary", size: "large"),
        ]

        let (segments, _) = GridLayoutEngine.segment(insights)

        #expect(segments.count == 2)
        if case let .fullWidth(i1) = segments[0] {
            #expect(i1.key == "1")
        } else {
            Issue.record("Expected fullWidth at index 0")
        }
        if case let .fullWidth(i2) = segments[1] {
            #expect(i2.key == "2")
        } else {
            Issue.record("Expected fullWidth at index 1")
        }
    }

    @Test("Single small insight produces one grid batch with one item")
    func singleSmall() {
        let insights = [makeInsight(key: "solo", type: "metric", size: "small")]
        let (segments, _) = GridLayoutEngine.segment(insights)

        #expect(segments.count == 1)
        if case let .gridBatch(batch) = segments[0] {
            #expect(batch.count == 1)
        } else {
            Issue.record("Expected gridBatch")
        }
    }

    @Test("Single wide insight produces one fullWidth segment")
    func singleWide() {
        let insights = [makeInsight(key: "solo", type: "trend", size: "wide")]
        let (segments, _) = GridLayoutEngine.segment(insights)

        #expect(segments.count == 1)
        if case .fullWidth = segments[0] {
            // pass
        } else {
            Issue.record("Expected fullWidth")
        }
    }

    // MARK: - Filtering

    @Test("Insights with unparseable cardType are filtered; invalid combos get fallback")
    func filteringBehavior() {
        let insights = [
            makeInsight(key: "valid1", type: "metric", size: "small"),
            makeInsight(key: "fallback1", type: "metric", size: "large"),
            makeInsight(key: "valid2", type: "trend", size: "wide"),
            makeInsight(key: "filtered1", type: "bogus", size: "small"),
            makeInsight(key: "fallback2", type: "metric", size: "tiny"),
        ]

        let (segments, filteredCount) = GridLayoutEngine.segment(insights)

        #expect(filteredCount == 1)
        #expect(segments.count == 3)

        if case let .gridBatch(batch) = segments[0] {
            #expect(batch.count == 2)
            #expect(batch[0].key == "valid1")
            #expect(batch[1].key == "fallback1")
        } else {
            Issue.record("Expected gridBatch at index 0")
        }

        if case let .fullWidth(insight) = segments[1] {
            #expect(insight.key == "valid2")
        } else {
            Issue.record("Expected fullWidth at index 1")
        }

        if case let .gridBatch(batch) = segments[2] {
            #expect(batch.count == 1)
            #expect(batch[0].key == "fallback2")
        } else {
            Issue.record("Expected gridBatch at index 2")
        }
    }

    @Test("Only unparseable cardType gets filtered; invalid combo gets fallback")
    func partialFiltering() {
        let insights = [
            makeInsight(key: "fallback", type: "metric", size: "large"),
            makeInsight(key: "filtered", type: "bogus", size: "small"),
        ]

        let (segments, filteredCount) = GridLayoutEngine.segment(insights)

        #expect(filteredCount == 1)
        #expect(segments.count == 1)

        if case let .gridBatch(batch) = segments[0] {
            #expect(batch.count == 1)
            #expect(batch[0].key == "fallback")
        } else {
            Issue.record("Expected gridBatch")
        }
    }

    @Test("Filtered count is zero when all insights are valid")
    func noFiltering() {
        let insights = [
            makeInsight(key: "1", type: "metric", size: "small"),
            makeInsight(key: "2", type: "trend", size: "wide"),
        ]

        let (_, filteredCount) = GridLayoutEngine.segment(insights)
        #expect(filteredCount == 0)
    }

    #if canImport(UIKit)
    @Test("Rendered AdaptiveCardGrid surfaces share equal row height")
    @MainActor
    func equalHeightRowContract() throws {
        let insights = [
            OverviewInsight(
                key: "left", cardType: "metric", cardSize: "medium",
                title: "Steps", content: "8,543"
            ),
            OverviewInsight(
                key: "right", cardType: "metric", cardSize: "medium",
                title: "Heart Rate", content: "68 BPM",
                suggestion: "Higher this week"
            )
        ]
        for isDark in [false, true] {
            let theme = Theme(isDark: isDark)
            let root = ScrollView {
                AdaptiveCardGrid(insights: insights)
                    .padding(16)
            }
            .environment(\.theme, theme)
            .background(theme.canvas)
            let controller = UIHostingController(rootView: root)
            let window = try overviewSnapshotWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
            window.overrideUserInterfaceStyle = isDark ? .dark : .light
            controller.overrideUserInterfaceStyle = window.overrideUserInterfaceStyle
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            let format = UIGraphicsImageRendererFormat()
            format.scale = 3.0
            let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
                #expect(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let bitmap = try #require(image.cgImage)
            // Sample blank vertical strips INSIDE the painted Card backgrounds,
            // before the text inset. This detects intrinsic-height surfaces even
            // when their transparent outer Grid slots have identical heights.
            let left = try surfaceRun(bitmap, x: 22 * 3, color: UIColor(theme.surface))
            let right = try surfaceRun(bitmap, x: 207 * 3, color: UIColor(theme.surface))
            #expect(left.count > 80 * 3)
            #expect(right.count > 80 * 3)
            #expect(abs(left.count - right.count) <= 1, "Painted sibling heights must agree within one pixel")
            #expect(abs(left.lowerBound - right.lowerBound) <= 1)
            #expect(abs(left.upperBound - right.upperBound) <= 1)
        }
    }

    private func surfaceRun(_ image: CGImage, x: Int, color: UIColor) throws -> Range<Int> {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        let expected = [red, green, blue].map { Int(($0 * 255).rounded()) }
        let stride = image.width * 4
        var pixels = [UInt8](repeating: 0, count: stride * image.height)
        return try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: stride,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            var best = 0..<0
            var start = 0
            for y in 0...image.height {
                let offset = y * stride + x * 4
                let matches = y < image.height && (0..<3).allSatisfy {
                    abs(Int(buffer[offset + $0]) - expected[$0]) <= 2
                }
                if !matches {
                    if y - start > best.count { best = start..<y }
                    start = y + 1
                }
            }
            return best
        }
    }
    #endif
}
