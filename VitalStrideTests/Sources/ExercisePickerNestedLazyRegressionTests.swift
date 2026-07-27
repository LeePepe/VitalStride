import Foundation
import Testing

@testable import VitalStride

/// Regression guard for the Exercise Picker 100%-CPU hang.
///
/// The picker groups exercises into equipment sections. Each section renders a
/// `LazyVGrid` of up to ~200 exercise cards. The outer section list MUST be an
/// eager `VStack`, NOT a `LazyVStack`: nesting a lazy grid inside a lazy stack
/// is a pathological SwiftUI combination. The outer lazy container cannot
/// derive a stable intrinsic size for the inner lazy grid, so every
/// prefetch-phase update re-expands the inner grid in full, recursing through
/// `ModifiedViewList.applyNodes` and pinning the main thread at 100% CPU with a
/// non-convergent `LazyLayoutViewCache.updatePrefetchPhases` loop. Section
/// count is bounded (≤18 equipment kinds), so the eager outer stack is cheap
/// and leaves exactly one lazy layer doing the card virtualization.
///
/// The hang is a SwiftUI layout-engine behavior that cannot be triggered from a
/// pure unit test, so this guards the source structure directly: if someone
/// reintroduces `LazyVStack` around the equipment sections, this fails.
@Suite("ExercisePicker nested-lazy hang regression")
struct ExercisePickerNestedLazyRegressionTests {

    /// Locate the picker source file relative to this test file, strip comment
    /// lines, and return the remaining code lines. Stripping comments keeps the
    /// structural guards from tripping on prose that merely *names* `LazyVStack`
    /// or `.safeAreaInset` in the explanatory doc comments.
    private func exercisePickerCodeLines() throws -> [String] {
        // This test lives at VitalStrideTests/Sources/…; the source lives at
        // VitalStride/Sources/ExercisePickerView.swift. Walk up to the repo
        // root and resolve the known path.
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // VitalStrideTests
            .deletingLastPathComponent() // repo root
        let source = repoRoot
            .appendingPathComponent("VitalStride")
            .appendingPathComponent("Sources")
            .appendingPathComponent("ExercisePickerView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)

        // Keep only lines whose first non-whitespace content is NOT a comment
        // marker (`//`, `///`, or a `*`/`/` continuation of a block comment).
        // This is a deliberately simple line filter — it does not parse
        // trailing or inline block comments — which is sufficient here because
        // the constructs we guard against (`LazyVStack(`, `.safeAreaInset(edge:`)
        // only ever appear as leading code, never trailing another statement.
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.hasPrefix("//")
                    && !trimmed.hasPrefix("*")
                    && !trimmed.hasPrefix("/*")
            }
    }

    @Test("Equipment section list is NOT wrapped in a LazyVStack")
    func outerSectionListIsEager() throws {
        let code = try exercisePickerCodeLines()

        // The inner per-section grid must stay lazy (it virtualizes the cards).
        #expect(
            code.contains(where: { $0.contains("LazyVGrid(") }),
            "Expected the per-section card grid to remain a LazyVGrid."
        )

        // The outer section list must NOT be lazy. A `LazyVStack(` construction
        // anywhere in this file would re-nest the pathological lazy-in-lazy
        // layout that caused the 100% CPU hang. We match the actual call form
        // `LazyVStack(` on non-comment lines so prose in doc comments that
        // merely names the type does not trip the guard.
        #expect(
            !code.contains(where: { $0.contains("LazyVStack(") }),
            """
            ExercisePickerView reintroduced a `LazyVStack`. The equipment \
            section list must be an eager `VStack` so the only lazy layer is \
            the inner per-section `LazyVGrid`. Nesting LazyVGrid inside \
            LazyVStack pins the main thread at 100% CPU (non-convergent \
            LazyLayoutViewCache.updatePrefetchPhases relayout).
            """
        )
    }

    @Test("Floating panel is not attached with safeAreaInset")
    func panelDoesNotUseSafeAreaInset() throws {
        let code = try exercisePickerCodeLines()

        // The floating search+filter panel must attach via `FloatingPanelAttachment`
        // (safeAreaBar on iOS 26 / overlay on iOS 18), never `.safeAreaInset`,
        // whose inset resolves inside the grid's lazy placement pass and forms
        // a non-convergent layout feedback loop with the grid. Match the actual
        // modifier call `.safeAreaInset(edge:` on non-comment lines so the
        // historical reference in doc comments does not trip the guard.
        #expect(
            !code.contains(where: { $0.contains(".safeAreaInset(edge:") }),
            """
            ExercisePickerView reintroduced `.safeAreaInset(edge:` for the \
            floating panel. Use `FloatingPanelAttachment` instead: safeAreaInset \
            feeds the panel height back into the grid's safe-area during \
            placement, forming a non-convergent SafeAreaInsets.resolve / \
            LazyVGrid loop.
            """
        )
    }
}
