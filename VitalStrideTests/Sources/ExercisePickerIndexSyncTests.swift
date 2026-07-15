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
}
