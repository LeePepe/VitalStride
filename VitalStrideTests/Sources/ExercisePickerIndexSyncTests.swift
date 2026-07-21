import Testing
import VitalModels

@testable import VitalStride

/// MY-1249 — Reproducible sync check for the ExercisePicker right-side
/// index bar. The bug was that scrolling the card grid did not update the
/// index-bar highlight because the `.scrollPosition(id:anchor:.top)`
/// binding lagged with lazy sections. The fix replaces that with
/// `onScrollTargetVisibilityChange`, which delivers the currently-visible
/// section ids; `firstVisibleEquipment(from:in:)` maps those ids to the
/// section that should own the highlight (the top-most on-screen section
/// in equipment order).
///
/// These tests exercise that mapping function directly. Together with the
/// `hitWidth == 44` assertion they lock the two acceptance criteria that
/// can be verified without a rendered view: highlight sync semantics and
/// ≥44pt index-bar hit target (Constitution §H).
@MainActor
@Suite("ExercisePicker index-bar sync (MY-1249)")
struct ExercisePickerIndexSyncTests {

    @Test("first visible id in equipment order wins the highlight")
    func firstVisibleWins() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        // Grid scrolled past barbell — barbell is off-screen, dumbbell &
        // machine are both partially visible. The top-most (dumbbell)
        // must own the highlight, not whichever id the scroll view
        // happens to report first.
        let visible: [Equipment] = [.machine, .dumbbell]

        let selected = ExercisePickerView.firstVisibleEquipment(from: visible, in: order)

        #expect(selected == .dumbbell)
    }

    @Test("scrolling to a later section moves the highlight")
    func highlightFollowsScroll() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]

        // Initial: barbell + dumbbell visible → barbell highlighted.
        let atTop = ExercisePickerView.firstVisibleEquipment(
            from: [.barbell, .dumbbell],
            in: order
        )
        #expect(atTop == .barbell)

        // Finger drags up: barbell scrolled off, dumbbell + machine visible.
        // Highlight MUST move to dumbbell — this is the exact regression
        // in MY-1249 (highlight stuck on barbell).
        let afterScroll = ExercisePickerView.firstVisibleEquipment(
            from: [.dumbbell, .machine],
            in: order
        )
        #expect(afterScroll == .dumbbell)

        // Keeps scrolling to the machine section — highlight follows.
        let atMachine = ExercisePickerView.firstVisibleEquipment(
            from: [.machine, .cable],
            in: order
        )
        #expect(atMachine == .machine)
    }

    @Test("empty visible list yields nil (no crash, no stale highlight)")
    func emptyVisibleReturnsNil() {
        let order: [Equipment] = [.barbell, .dumbbell]
        #expect(ExercisePickerView.firstVisibleEquipment(from: [], in: order) == nil)
    }

    @Test("visible id absent from order falls back to first visible")
    func absentIdFallback() {
        // Defensive: if the scroll view reports an id we did not list
        // (shouldn't happen, but guard against filter-race timing), the
        // helper still returns something rather than nil.
        let order: [Equipment] = [.barbell]
        let selected = ExercisePickerView.firstVisibleEquipment(
            from: [.dumbbell],
            in: order
        )
        #expect(selected == .dumbbell)
    }

    // Constitution §H: interactive hit targets must be at least 44pt.
    // Regressing this to a smaller value re-opens the "index bar hard to
    // hit with a thumb" complaint that motivated the original 44pt lane.
    @Test("index bar hit-target lane is at least 44pt")
    func hitTargetMeetsConstitution() {
        #expect(ExercisePickerView.equipmentIndexBarHitWidth >= 44)
    }

    /// MY-1272: the collapsed search pill is the entire hit target — its
    /// diameter MUST satisfy Constitution §H. If a future style change
    /// shrinks the pill for aesthetics, this test regresses first.
    @Test("collapsed search pill diameter is at least 44pt (MY-1272)")
    func collapsedSearchDiameterMeetsConstitution() {
        #expect(ExercisePickerView.collapsedSearchDiameter >= 44)
    }

    // MARK: - Callback / configuration path (P0 regression coverage)

    /// P0 regression from PR #256 review: each scroll target is a whole
    /// equipment section, and a single section can be far taller than the
    /// viewport (dumbbell has ≥200 exercises). If the visibility threshold
    /// stays at the SwiftUI default of `0.5`, such a section can never
    /// reach 50% visibility and gets omitted from `visibleIds`, leaving
    /// the highlight stale. This test locks the configured threshold to a
    /// value low enough that even a section only 5% on-screen still enters
    /// the callback payload — i.e. the fix cannot be silently reverted.
    @Test("visibility threshold is low enough to include viewport-taller sections")
    func visibilityThresholdIsLowEnoughForTallSections() {
        // Any section showing this fraction of itself or more must be
        // reported as visible. A viewport-taller section with only 5% of
        // its own height on-screen is a realistic worst case.
        let worstCaseSectionVisibleFraction: Double = 0.05

        #expect(ExercisePickerView.visibilityThreshold <= worstCaseSectionVisibleFraction)
        // Threshold must be a legal SwiftUI value (0.0 ... 1.0).
        #expect(ExercisePickerView.visibilityThreshold >= 0)
        #expect(ExercisePickerView.visibilityThreshold <= 1)
    }

    /// Exercises the real callback path (`applyVisibleIds`) that
    /// `onScrollTargetVisibilityChange` invokes — not just the ordering
    /// helper. Simulates the tall-section case: only one id is reported
    /// (because the previous section scrolled off and the next section
    /// is still just below the viewport). The setter MUST receive that
    /// single id so the highlight follows.
    @Test("callback path picks the top-visible section when only one id is reported")
    func callbackPathHandlesSingleTallSection() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        var applied: Equipment? = .barbell // stale

        // Dumbbell is the only section on-screen (huge section, fills the
        // viewport). Without a low threshold this would be an empty list;
        // WITH the low threshold, the single id arrives — and the
        // highlight must move to `.dumbbell` (not stay stale on barbell).
        ExercisePickerView.applyVisibleIds([.dumbbell], in: order) { applied = $0 }
        #expect(applied == .dumbbell)

        // Scroll further: only machine on-screen. Same contract.
        ExercisePickerView.applyVisibleIds([.machine], in: order) { applied = $0 }
        #expect(applied == .machine)
    }

    /// Callback path preserves the "top-most in equipment order wins"
    /// contract when the scroll view reports multiple ids (e.g. two
    /// shorter sections both on-screen). This is the classic case the
    /// original review flagged for regression coverage on the callback
    /// configuration path, not just on `firstVisibleEquipment`.
    @Test("callback path selects top-most on-screen section across multiple ids")
    func callbackPathSelectsTopMostAcrossIds() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        var applied: Equipment? = nil

        // Barbell (top-most) + dumbbell both visible.
        ExercisePickerView.applyVisibleIds([.dumbbell, .barbell], in: order) { applied = $0 }
        #expect(applied == .barbell)

        // Scrolled: dumbbell + machine both visible. Highlight moves to
        // dumbbell — this is the exact MY-1249 repro at the callback layer.
        ExercisePickerView.applyVisibleIds([.machine, .dumbbell], in: order) { applied = $0 }
        #expect(applied == .dumbbell)
    }

    /// Empty callback payload (nothing on-screen — e.g. the grid was
    /// filtered to zero rows mid-scroll) must clear the highlight rather
    /// than crash or leak a stale id through to the setter.
    @Test("callback path clears highlight when nothing is on-screen")
    func callbackPathClearsHighlightOnEmpty() {
        let order: [Equipment] = [.barbell, .dumbbell]
        var applied: Equipment? = .barbell

        ExercisePickerView.applyVisibleIds([], in: order) { applied = $0 }
        #expect(applied == nil)
    }

    // MARK: - Dedup guard (scroll-hang fix)
    //
    // `onScrollTargetVisibilityChange` fires on nearly every frame during a
    // finger scroll across ≥1000 exercises. The original callback wrote
    // `visibleEquipment` unconditionally, re-publishing `@State` (and forcing
    // a full-grid SwiftUI re-evaluation) even when the top-visible section had
    // not changed — the redundant per-frame churn that starved the main thread
    // and produced the "动作选择页面滚动" hang. The dedup-aware
    // `applyVisibleIds(_:in:current:using:)` overload must invoke the setter
    // ONLY on a genuine section change.

    /// When the resolved top-visible section equals `current`, the setter
    /// must NOT fire — this is the per-frame no-op that the fix suppresses.
    @Test("dedup: unchanged top-visible section does not write @State")
    func dedupSuppressesUnchangedWrite() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        var writeCount = 0
        var applied: Equipment? = .dumbbell

        // Same section still top-visible (payload jitters between frames but
        // dumbbell stays top-most). No write should occur.
        let resolved = ExercisePickerView.applyVisibleIds(
            [.dumbbell, .machine],
            in: order,
            current: .dumbbell
        ) { applied = $0; writeCount += 1 }

        #expect(resolved == .dumbbell)
        #expect(writeCount == 0, "unchanged section must not re-publish @State")
        #expect(applied == .dumbbell)
    }

    /// A genuine section change MUST still write exactly once so the
    /// highlight keeps following the scroll (the dedup cannot over-suppress).
    @Test("dedup: changed top-visible section writes exactly once")
    func dedupWritesOnGenuineChange() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        var writeCount = 0
        var applied: Equipment? = .barbell

        let resolved = ExercisePickerView.applyVisibleIds(
            [.dumbbell, .machine],
            in: order,
            current: .barbell
        ) { applied = $0; writeCount += 1 }

        #expect(resolved == .dumbbell)
        #expect(writeCount == 1)
        #expect(applied == .dumbbell)
    }

    /// A whole scroll gesture that surfaces the same section across many
    /// high-frequency callbacks must collapse to a single write — the crux
    /// of the hang fix. Simulates 100 frames reporting dumbbell as top-most.
    @Test("dedup: 100 same-section frames collapse to a single write")
    func dedupCollapsesHighFrequencyFrames() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        var writeCount = 0
        var current: Equipment? = .barbell

        for _ in 0..<100 {
            current = ExercisePickerView.applyVisibleIds(
                [.dumbbell, .machine],
                in: order,
                current: current
            ) { _ in writeCount += 1 }
        }

        // First frame changes barbell→dumbbell (1 write); the remaining 99
        // frames report the same top section and must all be suppressed.
        #expect(writeCount == 1, "high-frequency same-section frames must not each re-publish @State")
        #expect(current == .dumbbell)
    }

    /// Clearing to `nil` (grid emptied mid-scroll) is itself a change from a
    /// non-nil current and must write once; a subsequent empty frame while
    /// already `nil` must be suppressed.
    @Test("dedup: nil transition writes once then suppresses")
    func dedupHandlesNilTransition() {
        let order: [Equipment] = [.barbell, .dumbbell]
        var writeCount = 0

        var current: Equipment? = .barbell
        current = ExercisePickerView.applyVisibleIds([], in: order, current: current) {
            current = $0; writeCount += 1
        }
        #expect(current == nil)
        #expect(writeCount == 1)

        // Already nil — another empty frame must not write.
        _ = ExercisePickerView.applyVisibleIds([], in: order, current: current) {
            current = $0; writeCount += 1
        }
        #expect(writeCount == 1)
    }
}
