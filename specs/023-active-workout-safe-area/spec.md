# Feature Specification: Active Workout Safe-Area Stability

**Feature Branch**: `023-active-workout-safe-area`

**Created**: 2026-08-25

**Status**: Review candidate

**Input**: MY-1476 — stabilize keyboard show/hide behavior in `ActiveWorkoutView` so the scrollable content, snackbar, and add-exercise FAB do not jump or overlap.

**Constitution refs**: §II Swift 6 Strict Concurrency, §III SPM Package Priority / AppUI ownership, §IV XcodeGen Source of Truth, §Cross-Cutting Quality Bars A/G/H/I/K.

**Baseline relation**: Refines the baseline strength-training journey in `specs/000-baseline-existing-codebase/spec.md` User Story 1. It does not add a new workout or persistence capability.

## User Scenarios & Testing

### User Story 1 - Stable set editing across keyboard transitions (Priority: P1)

While editing a set in an active workout, the user can show and dismiss the custom numeric keyboard without the header, exercise list, snackbar, or add-exercise control making a duplicated jump or briefly occupying an invalid position.

**Why this priority**: Numeric set entry is the primary active-workout interaction. The current transition changes the system keyboard avoidance, the bottom safe-area subtree, and the top header/snackbar composition at the same time, which makes the core editing path visually unstable.

**Independent Test**: On an iPhone 16 Simulator with multiple exercises and sets, exercise keyboard show and hide while the snackbar state is none, rest, and undo. The focused row remains visible, the active snackbar appears exactly once, bottom controls do not overlap, and the final set remains scrollable above visible chrome.

**Acceptance Scenarios**:

1. **Given** a rest snackbar is visible, **when** the user focuses and then dismisses a weight or reps field, **then** the list and info header do not perform the former paired jump and the snackbar is visible in exactly one valid region throughout each settled state.
2. **Given** an undo snackbar is visible, **when** the keyboard appears or disappears, **then** the undo action remains reachable, does not overlap the keyboard or FAB, and VoiceOver focus follows the active presentation.
3. **Given** no snackbar is visible, **when** the keyboard appears or disappears, **then** no empty snackbar presentation becomes interactive or accessible and the FAB returns to its correct hidden-keyboard position without displacing the list twice.
4. **Given** the keyboard is hidden and a rest or undo snackbar is visible, **when** the user scrolls to the last set, **then** the FAB is above the snackbar, both remain inside the bottom safe area without intersecting, and the last set can scroll above them.
5. **Given** the keyboard is visible, **when** the user edits a row near the end of the workout, **then** the focused input row, active snackbar, and keyboard remain mutually unobscured without reading private keyboard geometry.
6. **Given** light and dark appearance, **when** the keyboard is shown and dismissed with an active snackbar, **then** consecutive before-show, after-show, and after-hide screenshots show stable margins and no transient overlap in either direction.

### Edge Cases

- Rapid focus changes that produce closely spaced keyboard show/hide notifications must settle into the latest visibility state without replaying stale geometry animations.
- When snackbar arbitration changes between none, rest, and undo while the keyboard is already visible, exactly one active snackbar remains interactive and accessible.
- Large Mode and the compact info band must use the same root layout contract even though their header content differs.
- Long localized undo text and accessibility Dynamic Type sizes must preserve the existing stable envelope and 44-point action targets.
- Backgrounding or navigating away during an active keyboard/snackbar state must not change timer, undo, or persistence behavior.

## Requirements

### Functional Requirements

- **FR-001**: The `ActiveWorkoutView` root MUST own one stable bottom safe-area composition across keyboard-visible and keyboard-hidden states; keyboard changes MUST NOT insert or delete the complete snackbar/FAB safe-area subtree.
- **FR-002**: The internal `ActiveWorkoutSnackbarLayout` interface MUST define one deterministic policy for the two keyboard states crossed with snackbar none, rest, and undo, and production and tests MUST exercise that same policy.
- **FR-003**: Keyboard visibility MUST drive only the necessary placement, visibility, and focus changes. The same geometry change MUST NOT be implicitly animated at both the root and a transitioning child.
- **FR-004**: With the keyboard hidden, the FAB MUST remain in the bottom safe area for all snackbar states; an active snackbar MUST not intersect it, and the FAB MUST be above the active snackbar.
- **FR-005**: With the keyboard visible, the focused input row and active snackbar MUST remain fully visible and unobscured by the keyboard. The implementation MUST NOT use private APIs or direct keyboard-frame probing.
- **FR-006**: At most one snackbar presentation MUST be interactive and exposed to accessibility. Existing undo-over-rest arbitration and VoiceOver focus migration MUST remain intact.
- **FR-007**: The last set row MUST be scrollable above every active lower overlay or reserved region in all six keyboard/snackbar combinations.
- **FR-008**: Regression tests MUST be written first and cover keyboard visible/hidden crossed with snackbar none/rest/undo through the production layout policy, including stable root avoidance, single active placement, non-overlap, and final-row clearance.
- **FR-009**: Verification MUST include iPhone 16 Simulator light/dark visual evidence for keyboard show and hide. Automated AppUI verification MUST use the layer command declared by `VitalStride/CONTEXT.md`.

### Non-Functional Requirements

- No public API changes; the layout seam remains internal to AppUI.
- Preserve Swift 6 strict concurrency and existing MainActor isolation (Constitution §II).
- Preserve Dynamic Type, VoiceOver, localized snackbar copy, and minimum hit targets (Quality Bars G/H/I).
- No new package dependency, target configuration, persistence model, telemetry, or logging.

## Scope

### Files in scope

- `VitalStride/Sources/ActiveWorkoutView.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift`
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarSafeAreaTests.swift`

### Files not to touch

- `Packages/**`
- `project.yml` and `VitalStride.xcodeproj/**`
- `VitalStride/Sources/SelectAllTextField.swift` and numeric parsing/input contracts
- Snackbar copy, timer lifecycle, undo arbitration, persistence, telemetry, and unrelated ActiveWorkout modules
- `VitalStrideTests/Sources/SnackbarAccessibilityUITests.swift` (must continue to pass unchanged)

### Interface impact

- Existing internal seam: `ActiveWorkoutSnackbarLayout` and its single call site in `ActiveWorkoutView`.
- Existing focus seam: `SnackbarFocusRouter` behavior remains compatible.
- Public signatures: none.

## Success Criteria

- **SC-001**: The automated regression matrix passes for all 6 keyboard/snackbar states and both keyboard transition directions.
- **SC-002**: Host geometry assertions show no FAB/snackbar intersection and no loss of final-row scroll clearance in any matrix state.
- **SC-003**: The focused row and active snackbar remain visible during keyboard presentation without private keyboard-geometry access.
- **SC-004**: iPhone 16 Simulator light/dark evidence covers keyboard show and hide with no transient header/list double jump or overlay intersection.
- **SC-005**: The full AppUI layer test command passes from the repository root.

## Assumptions

- The current custom numeric keyboard continues to publish UIKit keyboard show/hide notifications; replacing the keyboard implementation is out of scope.
- Existing `BottomSnackbarSlot` arbitration remains the source of none/rest/undo state.
- The FAB is not an editing action while the keyboard is visible; the layout policy suppresses its presentation while keeping the root composition structurally stable.
- No domain terminology, data model, ADR, or package boundary changes are required.

## Out of Scope

- Redesigning the custom numeric keyboard, snackbar visuals, text, or timer behavior.
- Changing set value parsing, select-all behavior, rest timing, undo semantics, or workout persistence.
- Adding a reusable package-level layout module or reading private keyboard geometry.
- watchOS or macOS feature work.
