import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// MY-1080 — single-pass numbering for `ActiveExerciseSection.rowContexts`.
///
/// Replaces the prior O(n² log n) render path (repeated `sortedSets` + per-row
/// re-walks) with a single O(n) pass. This test locks the numbering contract
/// so a regression that reintroduces per-row sorting can't silently drift the
/// displayed set numbers or the sub-set boundary flag.
@Suite("ActiveExerciseSection.rowContexts (MY-1080)")
struct ActiveExerciseRowContextsTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    @Test("Main-set numbering starts at zero and increments across sub-sets")
    func numbersMainSetsAndSubSets() throws {
        // Layout: main(80), sub(dropSet,68), sub(dropSet,58), main(90), main(0)
        // Expected mainSetNumber per row: 0, 1, 1, 1, 2
        // recentWeightKg per row: nil, 80, 80, 80, 90
        // isLastSubSet per row: false, false, true, false, false
        let sets = makeSets([
            (80, .working),
            (68, .dropSet),
            (58, .dropSet),
            (90, .working),
            (0, .working)
        ])

        let ctxs = ActiveExerciseSection.rowContexts(from: sets)

        #expect(ctxs.map(\.mainSetNumber) == [0, 1, 1, 1, 2])
        #expect(ctxs.map(\.recentWeightKg) == [nil, 80, 80, 80, 90])
        #expect(ctxs.map(\.isLastSubSet) == [false, false, true, false, false])
    }

    @Test("Empty input returns empty output")
    func emptyInput() {
        let ctxs = ActiveExerciseSection.rowContexts(from: [])
        #expect(ctxs.isEmpty)
    }

    @Test("Trailing sub-set is flagged isLastSubSet=true")
    func trailingSubSetIsLast() throws {
        let sets = makeSets([
            (100, .working),
            (85, .dropSet)
        ])
        let ctxs = ActiveExerciseSection.rowContexts(from: sets)
        #expect(ctxs[1].isLastSubSet == true)
        #expect(ctxs[1].mainSetNumber == 1)
    }

    @Test("Zero-weight main set does not advance recentWeightKg")
    func zeroWeightSkipsRecentUpdate() throws {
        // main(0) → recent stays nil; main(50) → recent=50; sub(45) sees 50
        let sets = makeSets([
            (0, .working),
            (50, .working),
            (45, .dropSet)
        ])
        let ctxs = ActiveExerciseSection.rowContexts(from: sets)
        #expect(ctxs.map(\.recentWeightKg) == [nil, nil, 50])
    }

    // MARK: - Helpers

    private func makeSets(_ items: [(Double, SetType)]) -> [ExerciseSet] {
        let context = ModelContext(container)
        return items.enumerated().map { idx, item in
            let set = ExerciseSet(
                order: idx,
                weight: item.0,
                reps: 8,
                setType: item.1,
                isUnilateral: false,
                weightRight: nil
            )
            context.insert(set)
            return set
        }
    }
}
