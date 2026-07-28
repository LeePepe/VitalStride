import Testing
@testable import DesignKit

// MARK: - Layout tokens (MY-1361) — badge/banner-scale tokens

/// The MY-1361 round-2 fixes introduced badge/banner-scale spacing +
/// radius tokens so `WorkoutSourceBadge` / `WorkoutListStateBanner` could
/// drop every hardcoded `.padding(4)` / `.padding(8)` / `.padding(12)` /
/// `RoundedRectangle(cornerRadius: 6)` / `.frame(minHeight: 44)` literal.
/// These tests pin the numeric values so a future accidental edit to
/// `Theme.swift` (or a rename that silently drops the token) breaks the
/// package build rather than silently drifting the visual layout of every
/// downstream consumer.
@Suite("Layout tokens — MY-1361 badge/banner scale")
struct LayoutTokensTests {
    @Test("Radius tokens have the expected numeric values")
    func radiusValues() {
        #expect(Radius.card == 14)
        #expect(Radius.inner == 10)
        #expect(Radius.badge == 6)
    }

    @Test("Radius tokens are strictly ordered small ≤ inner ≤ card")
    func radiusMonotonic() {
        #expect(Radius.badge < Radius.inner)
        #expect(Radius.inner < Radius.card)
    }

    @Test("Space tokens have the expected numeric values")
    func spaceValues() {
        #expect(Space.hair == 4)
        #expect(Space.chipVertical == 3)
        #expect(Space.inline == 8)
        #expect(Space.gap == 12)
        #expect(Space.cardPadding == 16)
        #expect(Space.minTapTarget == 44)
    }

    @Test("Chip-scale spacing is tighter than card-scale spacing")
    func spaceMonotonic() {
        #expect(Space.chipVertical < Space.hair)
        #expect(Space.hair < Space.inline)
        #expect(Space.inline < Space.gap)
        #expect(Space.gap < Space.cardPadding)
        #expect(Space.cardPadding < Space.minTapTarget)
    }

    @Test("Space.minTapTarget matches Apple HIG minimum (44pt)")
    func minTapTargetMatchesHIG() {
        // Apple Human Interface Guidelines minimum: 44 × 44 pt.
        // This value is load-bearing for the workout-list state banner
        // "Open Settings" CTA hit target — do NOT lower it.
        #expect(Space.minTapTarget == 44)
    }

    @Test("Space.contentMaxWidth is unaffected by the round-2 additions")
    func contentMaxWidthUnchanged() {
        #expect(Space.contentMaxWidth == 1200)
    }
}
