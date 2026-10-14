# Feature Specification: Active Workout Concurrency-Safe Animation Policy

**Feature Branch**: `026-active-workout-animation-policy`

**Created**: 2026-10-14

**Status**: Planning review candidate

**Input**: MY-1706 — replace stopped MY-1486 from current `main@e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` with a fresh concurrency-safe implementation of the reviewed ActiveWorkout single-animation-owner behavior.

**Constitution refs**: §II Swift 6 Strict Concurrency, §III AppUI ownership, §IV XcodeGen Source of Truth, §Cross-Cutting Quality Bars A/C/G/H/I/K.

**Baseline relation**: Refines the baseline strength-training journey in `specs/000-baseline-existing-codebase/spec.md` User Story 1. It adds no workout, persistence, or public-interface capability.

## User Scenarios & Testing

### User Story 1 - Stable set editing with one animation owner (Priority: P1)

While editing a set in an active workout, the user can show and dismiss the custom numeric keyboard without the header, exercise list, snackbar, or add-exercise control making a duplicated jump or occupying an invalid position. The same stable composition covers snackbar none, rest, and undo.

**Why this priority**: Numeric set entry is the primary active-workout interaction. Current `main` combines system keyboard avoidance, conditional bottom-subtree removal, conditional top composition, child transition, and root animation for the same state change.

**Independent Test**: On the production layout policy, exercise keyboard hidden/visible crossed with snackbar none/rest/undo. Verify the stable root, single active snackbar, bottom-control clearance, final-row clearance, and mutation-sensitive single-animation-owner invariant.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** rest or undo is active, **when** the keyboard is shown and dismissed, **then** one stable root composition remains mounted and exactly one valid snackbar presentation is interactive and accessible.
2. **US1/AC2** — **Given** any of the six settled keyboard/snackbar states, **when** production resolves layout and animation policy, **then** the policy reports exactly one root geometry-animation owner, no child geometry animation, and no child insertion/removal transition.
3. **US1/AC3** — **Given** the single-owner regression test, **when** a mutation adds a child animation driver, adds a child transition, or removes the root driver, **then** the test deterministically fails through the same policy production consumes.
4. **US1/AC4** — **Given** the keyboard is hidden, **when** a snackbar is active or absent, **then** the FAB and snackbar remain inside the bottom safe area without overlap and the final set scrolls above active lower chrome.
5. **US1/AC5** — **Given** the keyboard is visible, **when** the user edits a row near the end of the workout, **then** the focused row and active snackbar remain unobscured without keyboard-frame probing.
6. **US1/AC6** — **Given** compact or Large Mode and existing accessibility settings, **when** state changes, **then** both modes use the same policy and existing focus, Dynamic Type, localization, and hit-target behavior remain valid.

### Edge Cases

- Rapid visibility notifications settle to the newest state without replaying stale geometry ownership.
- Snackbar arbitration may change among none, rest, and undo while the keyboard is already visible; only one presentation becomes interactive and accessible.
- A Swift concurrency check must not require `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` around SwiftUI values.
- Long localized undo text and accessibility Dynamic Type sizes retain the existing stable envelope and 44-point actions.
- Backgrounding or navigation during an active state does not change timer, undo, persistence, or telemetry behavior.

## Behaviour Contract

### Existing behaviour

At the declared base:

- `ActiveWorkoutView` conditionally removes the complete bottom safe-area child while the keyboard is visible and conditionally replaces the standalone header with the top snackbar composition.
- The bottom child has an insertion/removal transition while the root separately animates keyboard and snackbar state.
- `ActiveWorkoutSnackbarLayout` owns stable content envelopes and top/bottom rendering helpers, but no production-consumed policy describes root and child animation/transition ownership.
- `ActiveWorkoutSnackbarLayoutTests` verifies a pass-through FAB wrapper and edge selection but cannot reject an added child animation owner, an added child transition, or a missing root animation owner.

### Compatibility

- Preserve `BottomSnackbarSlot` undo-over-rest arbitration, `SnackbarFocusRouter`, stable snackbar envelopes, localized copy, Dynamic Type, VoiceOver representation, and 44-point actions.
- Preserve timer, undo, input parsing, persistence, telemetry, compact/Large Mode content, and public interfaces.
- Preserve existing tests; `VitalStrideTests/Sources/ActiveWorkoutSnackbarSafeAreaTests.swift` and `VitalStrideUITests/Sources/SnackbarAccessibilityUITests.swift` remain unchanged and continue to pass.
- Remain entirely inside the AppUI layer with no package, project configuration, data-model, or ADR change.

### Removed behaviour

The Owner decision recorded on MY-1486 authorizes removal of:

- keyboard-driven insertion/deletion of the complete bottom safe-area subtree;
- duplicate animation/transition ownership for the same root geometry change;
- production-unused or non-mutation-sensitive assertions as proof of the single-owner policy.

No other behavior, acceptance criterion, or existing test may be removed or weakened.

## Requirements

### Functional Requirements

- **FR-001**: `ActiveWorkoutView` MUST keep one root bottom safe-area composition structurally mounted across keyboard-hidden and keyboard-visible states.
- **FR-002**: The internal `ActiveWorkoutSnackbarLayout` interface MUST define one deterministic production-consumed policy for keyboard hidden/visible crossed with snackbar none/rest/undo.
- **FR-003**: That policy MUST describe root geometry-animation ownership, child geometry-animation ownership, and child insertion/removal transition ownership so production and tests can enforce exactly one root owner and no child transition.
- **FR-004**: SwiftUI-bearing animation policy values MUST be constructed or accessed under `@MainActor`. The implementation MUST NOT introduce `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.
- **FR-005**: Regression coverage MUST be mutation-sensitive and fail for each of these independent changes: adding a child animation driver, adding a child transition, or omitting the root animation driver.
- **FR-006**: With the keyboard hidden, the FAB MUST be above an active snackbar without intersection; with the keyboard visible, the focused row and active snackbar MUST clear the keyboard without private API or frame probing.
- **FR-007**: At most one snackbar presentation MUST be interactive and exposed to accessibility; existing arbitration and focus migration MUST remain intact.
- **FR-008**: The final set MUST remain scrollable above all active lower chrome; compact and Large Mode MUST use the same policy.
- **FR-009**: The implementation diff MUST contain exactly the three declared AppUI paths and MUST remove or weaken no existing test.

### Non-Functional Requirements

- Swift 6 strict concurrency with actor isolation rather than unchecked/unsafe escape (Constitution §II and Quality Bar C).
- Internal-only AppUI interface; no public signature, package dependency, schema, logging, telemetry, or target configuration change.
- No copying, cherry-picking, or reuse of stopped MY-1486 local candidate `c563cc108c11e97646cb95bf6bc3cb288b0c781d`; implementation is derived from this reviewed contract and current `main`.

## Scope

### Files in scope

- `VitalStride/Sources/ActiveWorkoutView.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift`

### Files not to touch

- Every other repository path, including `VitalStrideTests/Sources/ActiveWorkoutSnackbarSafeAreaTests.swift`
- `Packages/**`, `project.yml`, and `VitalStride.xcodeproj/**`
- `VitalStride/Sources/SelectAllTextField.swift`
- `VitalStrideUITests/Sources/SnackbarAccessibilityUITests.swift`
- Snackbar copy, timer/arbitration/persistence/telemetry, and unrelated ActiveWorkout modules
- MY-1486's registered workspace, branch, local candidate, and Draft PR #420

### Interface impact

- Existing internal seam: `ActiveWorkoutSnackbarLayout` and its sole `ActiveWorkoutView` call site.
- Existing focus seam: `SnackbarFocusRouter` remains compatible.
- Public signatures: none.

## Success Criteria

- **SC-001**: Automated policy coverage passes for all six keyboard/snackbar states and both keyboard transition directions.
- **SC-002**: The mutation-sensitive test rejects all three unauthorized ownership mutations independently.
- **SC-003**: Focused verification passes with zero failures on the declared iPhone 17 Simulator destination.
- **SC-004**: The exact implementation diff contains only the three authorized AppUI paths and no unchecked/unsafe concurrency escape.
- **SC-005**: After normal delivery, parked MY-1487 can run the full AppUI and visual evidence gate against the successor revision without using MY-1486 or Draft #420 as an input.

## Assumptions

- Existing public UIKit keyboard show/hide notifications remain the visibility source.
- `BottomSnackbarSlot` remains the source of none/rest/undo arbitration.
- The FAB is not an editing action while the keyboard is visible; the root composition remains structurally stable while presentation is suppressed.
- No domain term, persisted entity, package seam, or ADR changes.

## Out of Scope

- Redesigning the keyboard, snackbar visuals/copy, timer, undo, parsing, persistence, or telemetry.
- Adding a checked-Sendable descriptor abstraction; the approved design extends the existing `@MainActor` SwiftUI seam instead.
- Adding or modifying tests outside `ActiveWorkoutSnackbarLayoutTests.swift`.
- Modifying or closing Draft PR #420 before a successor PR is published.
- watchOS or macOS feature work.
