# Contract: Active Workout Layout Composition

## Interface boundary

The internal `ActiveWorkoutSnackbarLayout` seam owns the relationship among:

- keyboard visibility;
- active snackbar slot (`none`, `rest`, or `undo`);
- bottom safe-area reservation and FAB presentation;
- top snackbar presentation when required;
- hit testing, accessibility representation, and focus routing.

`ActiveWorkoutView` supplies state and view content once. It does not independently decide header replacement, complete bottom-subtree removal, and animation for the same keyboard change.

No public interface is added or changed.

## State matrix

| Keyboard | Snackbar | Settled presentation contract | Scroll/interaction contract |
|---|---|---|---|
| Hidden | None | Stable bottom composition is mounted; FAB is visible; no snackbar is visible, interactive, or accessible. | Final set scrolls above the FAB and device bottom safe area. |
| Hidden | Rest | FAB and one rest snackbar are visible in the bottom region; FAB is above the snackbar; frames do not intersect. | Final set scrolls above both controls; rest actions keep 44-point targets. |
| Hidden | Undo | FAB and one undo snackbar are visible in the bottom region; FAB is above the snackbar; frames do not intersect. | Final set scrolls above both controls; undo action and focus remain reachable. |
| Visible | None | Stable root composition remains mounted; FAB presentation is suppressed; no snackbar is visible, interactive, or accessible. | Focused row remains visible above the keyboard; no empty snackbar gap receives interaction. |
| Visible | Rest | Stable root composition remains mounted; exactly one rest snackbar is presented in the keyboard-safe region; inactive duplicate content is inert and inaccessible. | Focused row, rest snackbar, and keyboard do not overlap. |
| Visible | Undo | Stable root composition remains mounted; exactly one undo snackbar is presented in the keyboard-safe region; focus migrates to the active presentation. | Focused row, undo action, and keyboard do not overlap. |

## Transition invariants

1. Keyboard show/hide never inserts or deletes the complete root bottom safe-area composition.
2. One geometry change has one animation owner; root implicit animation and child insertion/removal transition do not both drive it.
3. Snackbar state changes do not alter the root's structural identity.
4. At most one snackbar presentation has opacity, hit testing, accessibility representation, or snackbar focus at a time.
5. Rapid notifications settle to the newest keyboard visibility and do not replay stale placement.
6. Compact and Large Mode header content obey the same composition contract.

## Preserved contracts

- Undo continues to outrank rest according to existing `BottomSnackbarSlot` arbitration.
- `SnackbarFocusRouter` continues to select the active top or bottom focus target.
- Existing stable-height undo/rest envelopes, localized copy, Dynamic Type behavior, and minimum hit targets remain unchanged.
- The custom numeric keyboard and `SelectAllTextField` input semantics remain unchanged.

## Verification surface

- Table-driven policy tests cover all six settled states.
- Transition tests cover hidden→visible and visible→hidden with none, rest, and undo.
- Hosted SwiftUI geometry verifies bottom containment, FAB/snackbar non-intersection, single active placement, and final-row clearance.
- The revision-keyed generic Debug build is clean-built and its bundle identifier is asserted before installation and launch on one dedicated iPhone 16; two continuous recordings and the settled no-snackbar screenshot all use that same explicit UDID.
- The light and dark recordings each span the full keyboard show and hide animations with an active snackbar and a final-row edit; the settled light screenshot proves no-snackbar FAB spacing and final-row clearance.
