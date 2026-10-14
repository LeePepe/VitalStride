# Contract: Active Workout Layout and Animation Policy

## Interface

The internal `ActiveWorkoutSnackbarLayout` seam owns:

- keyboard visibility and active snackbar slot (`none`, `rest`, or `undo`);
- stable root bottom-safe-area mounting;
- top/bottom presentation and FAB visibility/reservation;
- root geometry-animation ownership;
- child geometry-animation ownership;
- child insertion/removal transition ownership;
- single active interaction/accessibility placement.

`ActiveWorkoutView` supplies current state and view content once and derives its relevant presentation modifiers from this policy. It does not independently decide complete subtree removal, root animation, child animation, or child transition for the same geometry change.

No public interface is added or changed.

## Actor isolation

- SwiftUI-bearing policy construction and consumption are `@MainActor` isolated.
- The policy is UI-local and does not cross actors or claim sendability.
- `@unchecked Sendable`, `nonisolated(unsafe)`, and `@preconcurrency` are prohibited.
- Snackbar-local progress animation that does not own root safe-area geometry is outside this contract.

## State matrix

| Keyboard | Snackbar | Settled presentation | Scroll/interaction |
|---|---|---|---|
| Hidden | None | Stable bottom composition mounted; FAB visible; no snackbar visible, interactive, or accessible. | Final set clears the FAB and device safe area. |
| Hidden | Rest | FAB and exactly one rest snackbar visible; FAB above snackbar; no frame intersection. | Final set clears both; rest actions retain 44-point targets. |
| Hidden | Undo | FAB and exactly one undo snackbar visible; FAB above snackbar; no frame intersection. | Final set clears both; undo remains reachable. |
| Visible | None | Same root composition mounted; FAB presentation suppressed; no active snackbar. | Focused row clears keyboard; no empty interactive region. |
| Visible | Rest | Same root composition mounted; exactly one rest snackbar in keyboard-safe placement. | Focused row, snackbar, and keyboard do not overlap. |
| Visible | Undo | Same root composition mounted; exactly one undo snackbar in keyboard-safe placement. | Focused row and undo remain reachable; focus migrates correctly. |

## Transition and ownership invariants

1. Keyboard show/hide never inserts or deletes the complete root bottom-safe-area composition.
2. Production policy reports exactly one root geometry-animation owner.
3. Production policy reports no child geometry-animation owner.
4. Production policy reports no child insertion/removal transition owner.
5. Caller modifiers derive from the policy rather than reintroducing a second hard-coded owner.
6. Snackbar state changes do not alter root structural identity.
7. At most one snackbar presentation has hit testing, accessibility representation, or snackbar focus.
8. Rapid notifications settle to the newest keyboard state.
9. Compact and Large Mode use the same policy.

## Mutation contract

The regression surface must independently reject each mutation:

- root owner present plus child animation owner present;
- root owner present plus child transition present;
- root owner absent.

A test that only samples geometry trajectory, checks a root-only constant, or exercises a production-unused resolver does not satisfy this contract.

## Preserved contracts

- Existing `BottomSnackbarSlot` undo-over-rest arbitration.
- Existing `SnackbarFocusRouter` focus migration.
- Stable undo/rest envelopes, localized copy, Dynamic Type, VoiceOver representation, and minimum hit targets.
- Custom numeric keyboard, `SelectAllTextField`, timer, undo, persistence, and telemetry semantics.
- Existing read-only safe-area and accessibility tests.

## Verification surface

- Table-driven production-policy coverage for all six settled states.
- Both keyboard transition directions.
- Three independent ownership mutations.
- Existing safe-area geometry suite run unchanged.
- Focused iPhone 17 Simulator command for MY-1706, followed by the full AppUI and iPhone 16 evidence gate owned by MY-1487.
