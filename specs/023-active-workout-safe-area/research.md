# Research: Active Workout Safe-Area Stability

## R1 — Feature ownership

**Finding**: `specs/017-workout-keyboard-redesign/spec.md` explicitly excludes `ActiveWorkoutView` keyboard wiring. No current feature spec or branch covers MY-1476.

**Decision**: Create `023-active-workout-safe-area` rather than mutate feature 017.

## R2 — Root cause

**Finding**: One keyboard notification currently causes three coupled layout changes: system keyboard avoidance, deletion/insertion of the entire bottom inset child, and replacement of the standalone header with the top snackbar composition. A move/opacity child transition and root implicit animations also observe the same state.

**Decision**: Treat conditional root composition and duplicate animation ownership as the regression surface. Timer, undo, parsing, and snackbar content are not causal and remain out of scope.

## R3 — Module seam

**Finding**: `ActiveWorkoutSnackbarLayout` already hides stable-envelope, top/bottom composition, accessibility, and geometry behavior behind an internal interface. `ActiveWorkoutView` is its only production caller.

**Decision**: Deepen this existing module. Production and tests will use one keyboard-aware layout policy; no new package or public interface is needed.

## R4 — Test gaps

**Finding**: Current tests prove isolated static size, non-overlap, focus routing, and accessibility behavior. They do not toggle keyboard state through one production policy, cover all six keyboard/snackbar combinations, detect removal of the entire inset child, or prove final-row clearance.

**Decision**: Replace production-unused edge/pass-through confidence with a table-driven production-policy matrix and host geometry assertions. Preserve the broader safe-area and accessibility suites.

## R5 — Keyboard geometry

**Finding**: The app already receives keyboard show/hide state from public UIKit notifications. Reading or predicting the keyboard frame would add brittle coupling and is forbidden by MY-1476.

**Decision**: Use visibility state only. Let system safe-area behavior and the stable root composition provide avoidance; add no private API or frame observer.

## R6 — Verification destinations

**Finding**: MY-1476 requests iPhone 16 visual evidence, while the current AppUI layer frontmatter declares iPhone 17 for the authoritative test command.

**Decision**: Run automated focused and full AppUI tests on iPhone 17, build with the generic iOS Simulator destination, then launch and capture the full light/dark transitions on iPhone 16.

## R7 — Planning outputs

**Finding**: No data, schema, domain language, or cross-layer contract changes.

**Decision**: Provide a behavioral layout contract and quickstart. Omit `data-model.md` and ADR changes.

## Unresolved Questions

None. Product behavior, scope, layer ownership, and verification surfaces are deterministic from the issue and repository evidence.
