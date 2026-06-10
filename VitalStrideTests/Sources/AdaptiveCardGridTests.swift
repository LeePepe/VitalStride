import Foundation
import Testing
import AIService

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
}
