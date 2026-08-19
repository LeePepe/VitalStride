import Testing
import TelemetryKit
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

    // MARK: - MY-1338: drag-vs-scroll race
    //
    // Root cause of the "highlight jumps to neighbour" glitch: the side index
    // bar's drag `onSelect` calls `gridProxy.scrollTo(equipment, anchor: .top)`
    // which triggers its own `onScrollTargetVisibilityChange` bursts. Those
    // bursts arrive with a stale/out-of-order top-visible payload (the
    // freshly-scrolled section is not yet at the top, so the previous section
    // still qualifies as top-most), and if the scroll-callback overwrites
    // `visibleEquipment` mid-drag, the highlight visibly jumps to the neighbour
    // before snapping to the finger's actual target on the next frame. The
    // fix makes the drag the sole authority: while `draggedEquipment != nil`
    // the reducer ignores scroll-derived payloads and returns `current`
    // unchanged. When the drag ends, the next scroll callback reconciles the
    // highlight to whatever section is actually top-visible.

    /// Ignoring scroll-derived visibility during drag is the crux of MY-1338.
    /// The reducer must NOT invoke the setter with the racing payload while
    /// `isDragging == true`, even when the payload's top-visible section
    /// differs from `current` — otherwise the finger's target flickers
    /// through the neighbour.
    @Test("drag suppresses scroll-derived highlight write (MY-1338)")
    func dragSuppressesScrollWrite() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        var writeCount = 0
        var current: Equipment? = .machine // drag has scrubbed to machine

        // Scroll callback fires mid-drag with an OLDER section (barbell)
        // reported top-visible — this is the racing payload. Without the
        // drag-owns-highlight rule, this would flip `current` back to barbell
        // and the user would see the highlight jump.
        let resolved = ExercisePickerView.applyVisibleIds(
            [.barbell, .dumbbell],
            in: order,
            current: current,
            isDragging: true
        ) { current = $0; writeCount += 1 }

        #expect(resolved == .machine, "drag target must be preserved during scrub")
        #expect(current == .machine, "drag target must not be overwritten by scroll payload")
        #expect(writeCount == 0, "no @State write allowed while drag owns the highlight")
    }

    /// A high-frequency scroll burst during a drag must produce zero writes —
    /// the drag reducer is a hard mute on the scroll path.
    @Test("drag suppresses 100 scroll frames without writing (MY-1338)")
    func dragSuppressesHighFrequencyScroll() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        var writeCount = 0
        var current: Equipment? = .cable

        for _ in 0..<100 {
            _ = ExercisePickerView.applyVisibleIds(
                [.barbell, .dumbbell],
                in: order,
                current: current,
                isDragging: true
            ) { current = $0; writeCount += 1 }
        }

        #expect(writeCount == 0)
        #expect(current == .cable)
    }

    /// After drag ends, the next scroll-callback frame MUST reconcile
    /// `visibleEquipment` to the actual top-visible section reported by the
    /// scroll view — otherwise the highlight would freeze on the drag target
    /// even when the grid subsequently scrolls independently.
    @Test("drag end reconciles highlight to actual top-visible section (MY-1338)")
    func dragEndReconcilesToScroll() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine, .cable]
        var writeCount = 0
        var current: Equipment? = .machine // last drag target

        // Drag has ended; scroll animations settle; the grid is actually
        // top-anchored at `.dumbbell` (perhaps the animated scrollTo(.machine)
        // did not fully reach the top before the finger lifted). The next
        // callback MUST update the highlight.
        _ = ExercisePickerView.applyVisibleIds(
            [.dumbbell, .machine],
            in: order,
            current: current,
            isDragging: false
        ) { current = $0; writeCount += 1 }

        #expect(current == .dumbbell)
        #expect(writeCount == 1)
    }

    /// The non-drag reducer path must still dedup — the drag-aware overload
    /// must not accidentally re-enable the per-frame `@State` churn that
    /// MY-1249 fixed. Regression-guards the interaction between the two.
    @Test("non-drag reducer still dedups unchanged frames (MY-1338)")
    func nonDragReducerDedups() {
        let order: [Equipment] = [.barbell, .dumbbell]
        var writeCount = 0
        var current: Equipment? = .dumbbell

        _ = ExercisePickerView.applyVisibleIds(
            [.dumbbell],
            in: order,
            current: current,
            isDragging: false
        ) { current = $0; writeCount += 1 }

        #expect(writeCount == 0)
        #expect(current == .dumbbell)
    }

    /// Existing 4-argument overload delegates to the drag-aware overload with
    /// `isDragging: false` — regression cover so the pre-MY-1338 call sites
    /// (and their tests above) keep the same contract.
    @Test("legacy 4-arg overload delegates to non-drag path (MY-1338)")
    func legacyOverloadDelegatesToNonDrag() {
        let order: [Equipment] = [.barbell, .dumbbell, .machine]
        var writeCount = 0
        var current: Equipment? = .barbell

        // Same payload as `dedupWritesOnGenuineChange` — legacy overload
        // must write exactly once when the top-visible section changes.
        let resolved = ExercisePickerView.applyVisibleIds(
            [.dumbbell, .machine],
            in: order,
            current: current
        ) { current = $0; writeCount += 1 }

        #expect(resolved == .dumbbell)
        #expect(current == .dumbbell)
        #expect(writeCount == 1)
    }

    // MARK: - MY-1338: telemetry identifier canonicalisation
    //
    // The `exercisePickerSectionJump` event carries `from` / `to` / `source`
    // as `TelemetryIdentifier`. `TelemetryIdentifier.init(validating:)` rejects
    // non-canonical strings, which is how Constitution §V + §I keep raw
    // display names and localized text out of telemetry. These tests lock the
    // helper that maps `Equipment?` → `TelemetryIdentifier` so a future
    // rename that introduces a non-ASCII case name fails here first, and so
    // the two source-tag literals (`"scroll"` / `"drag"`) cannot silently
    // become free-form strings.

    @Test("equipment maps to canonical telemetry identifier (MY-1338)")
    func equipmentMapsToCanonicalIdentifier() {
        // Every Equipment case's rawValue is ASCII lowercase — passing
        // TelemetryIdentifier.init(validating:) is a construction-time
        // guarantee. Exercise the complete taxonomy so a future non-canonical
        // rename fails here.
        #expect(Equipment.allCases.count == 29)
        for equipment in Equipment.allCases {
            let identifier = ExercisePickerView.telemetryIdentifier(for: equipment)
            #expect(identifier.rawValue == equipment.rawValue)
        }
    }

    @Test("nil equipment maps to canonical sentinel (MY-1338)")
    func nilEquipmentMapsToSentinel() {
        #expect(
            ExercisePickerView.telemetryIdentifier(for: nil)
                == ExercisePickerView.sectionJumpNone
        )
    }

    @Test("section-jump source identifiers are canonical constants (MY-1338)")
    func sourceIdentifiersAreCanonical() {
        #expect(ExercisePickerView.sectionJumpSourceScroll.rawValue == "scroll")
        #expect(ExercisePickerView.sectionJumpSourceDrag.rawValue == "drag")
        #expect(ExercisePickerView.sectionJumpNone.rawValue == "none")
    }

    // MARK: - MY-1338: fixed-size section preview popup
    //
    // The section-preview popup (visible during scrub) previously grew
    // horizontally with long equipment names via `minWidth: 140`, which made
    // the surface visibly resize per scrub target and drift off centre. The
    // fix locks a hard `width × height`; long names truncate/scale inside.

    @Test("section preview popup dimensions are locked (MY-1338)")
    func sectionPreviewPopupDimensionsAreLocked() {
        // Any change here should be intentional and visible in a diff.
        #expect(ExercisePickerView.sectionPreviewPopupWidth == 160)
        #expect(ExercisePickerView.sectionPreviewPopupHeight == 160)
        // Width and height must be equal so the popup is a stable square,
        // not a rectangle that reads as "resized" between scrub frames.
        #expect(
            ExercisePickerView.sectionPreviewPopupWidth
                == ExercisePickerView.sectionPreviewPopupHeight
        )
    }
}
