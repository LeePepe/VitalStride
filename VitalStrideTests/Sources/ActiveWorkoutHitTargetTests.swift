import SwiftUI
import Testing

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

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
    /// Constitution P1-H floor. The fix routes the chip through
    /// `SetRow.smartProgressionChipHitTargetContainer` — a frame of side
    /// `ActiveWorkoutHitTarget.side` with `contentShape(Rectangle())`.
    ///
    /// This test does NOT re-check the token constant (that is what the
    /// two tests above already cover). Instead it renders the exact
    /// container the chip uses around a deliberately tiny 4pt label and
    /// asserts the *rendered* container height still meets the 44pt floor.
    /// If a future refactor removes `.frame(minHeight:)`, swaps in a
    /// smaller value, or replaces the container with a raw label, the
    /// hosting-controller measurement collapses to the 4pt intrinsic size
    /// and the test fails loudly — which is exactly the review probe the
    /// prior token-only assertion was missing.
    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("SetRow.smartProgressionChip renders a >=44pt hit region (MY-1208)")
    func smartProgressionChipRendersHitTargetContainer() {
        // A 4x4pt label — well below the 44pt floor — makes any regression
        // that bypasses the container immediately observable at ~4pt.
        let tinyLabel = Color.clear.frame(width: 4, height: 4)
        let container = SetRow.smartProgressionChipHitTargetContainer {
            tinyLabel
        }
        let host = UIHostingController(rootView: container)
        // sizeThatFits with .zero forces SwiftUI to resolve intrinsic size,
        // so the returned height reflects the container's own contract
        // (the 44pt minHeight) rather than any parent's imposed frame.
        let rendered = host.sizeThatFits(in: .zero)
        #expect(
            rendered.height >= ActiveWorkoutHitTarget.side,
            "Chip container rendered \(rendered.height)pt tall; must be >= \(ActiveWorkoutHitTarget.side)pt (Constitution P1-H). The label intrinsic size is 4pt, so any value near 4 means the .frame(minHeight:) was removed or shrunk."
        )
    }
    #endif
}
