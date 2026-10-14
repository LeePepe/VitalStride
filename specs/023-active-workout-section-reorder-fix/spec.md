# Feature Specification: Active Workout Exercise Section Reorder Fix

**Feature Branch**: `023-active-workout-section-reorder-fix`

**Created**: 2026-08-25

**Revised**: 2026-10-14 — reconciled with current `main@7fc46752b36d1b2469209b96c50801419315987c`

**Status**: Review candidate

**Input**: MY-1473 — the active-workout screen already exposes edit mode, but users cannot reliably move one exercise section before or after another. Owner decision `eb00fa65-5302-4150-99b4-d742c9b186aa` authorizes one narrow XCUITest and a DEBUG-only test entry/fixture in `VitalStrideApp.swift` so the actual interaction has red-before/green-after coverage. This revision rebases the planning package on verified `LeePepe/VitalStride` `main@7fc46752b36d1b2469209b96c50801419315987c` after MY-1706 changed `ActiveWorkoutView.swift`.

**Constitution refs**: Core Principles II/III/VII; Cross-Cutting Quality Bars A/C/D/E/G/H/I; Planning Review / Dual-Approval Gate

## Existing Behaviour

- `ActiveWorkoutView` shows `EditButton` when the active workout has more than one exercise.
- `exerciseList` sorts existing `WorkoutExercise` values by `order`, renders one `ActiveExerciseSection` per exercise, and attaches `.onMove` to the outer `ForEach`; `moveExercises(from:to:)` moves the sorted values and rewrites contiguous order values.
- The shipped `ExerciseManagementTests.reorderExercises` copies the movement and renumbering algorithm in test code. It proves those copied mutations, not that the production whole-section interaction can start or complete.
- `VitalStrideApp.swift` already contains unrelated, launch-argument-gated DEBUG UI-test harnesses, and `project.yml` already discovers `VitalStrideUITests/Sources/**`; no target configuration change is needed.
- MY-1706 changed the same source file above `exerciseList`: current `body` derives `ActiveWorkoutSnackbarLayout.policy`, keeps a stable policy-driven header/bottom safe-area composition, and gives root geometry animation ownership to `.activeWorkoutRootAnimation(policy:)`. The reorder symbols and behavior above are unchanged from the prior planning reference.

## Compatibility

- Preserve the current MY-1706 snackbar/FAB placement, keyboard-state composition, `@MainActor` animation policy, accessibility focus routing, and single root animation ownership in `ActiveWorkoutView.body`.
- Preserve existing `ActiveExerciseSection` internals, set/sub-set edit and delete behavior, localized exercise text, template/picker ordering, ordinary Debug/Release startup, and all public/package/schema contracts.
- The authorized DEBUG fixture remains opt-in and isolated. Its dedicated launch argument must select deterministic isolated storage and suppress ordinary exercise-catalog seeding without changing the existing ExercisePicker flag/container path or snackbar harness. With all test arguments absent, current app startup behaves exactly as before.

## Removed Behaviour

- Replace only the unreliable assumption that native row `.onMove` can expose a usable move entry for a `ForEach` whose rendered children are whole SwiftUI sections.
- No existing test is removed or weakened. The copied reorder unit test may be replaced or strengthened only by invoking the production seam and adding save/fresh-context proof.
- No MY-1706 behavior, set/sub-set behavior, toolbar behavior, localization, package code, project configuration, or companion-target behavior is removed. The authority for the interaction/test-surface change is Owner decision `eb00fa65-5302-4150-99b4-d742c9b186aa`.

## User Scenarios & Testing

### User Story 1 - Reorder whole exercise sections (Priority: P1)

While editing an active workout that contains multiple exercises, a user can identify a move control for every exercise section, move a section across its siblings, and see the new exercise order immediately and after reopening the workout.

**Why this priority**: Reordering exercises is the requested outcome. The current edit affordance is present but does not complete the journey.

**Independent Test**: A launch-argument-gated DEBUG fixture presents the production active-workout screen with three distinguishable exercises. One XCUITest enters edit mode, performs the actual whole-section drag from C-before-A, observes C/A/B immediately, leaves and re-enters the workout, and observes C/A/B again. The harness and XCUITest are added before the production repair so RED is the unchanged interaction failing to complete—not a missing symbol, missing fixture, or compile failure.

**Acceptance Scenarios**:

1. **Given** an active workout with three exercise sections ordered A, B, C, **when** the user enters edit mode, **then** each whole exercise section exposes a discoverable move control and the controls do not target individual set rows.
2. **Given** A, B, C in edit mode, **when** the user moves C before A, **then** the visible order becomes C, A, B immediately and the stored exercise order values become exactly 0, 1, 2 with no duplicates or gaps.
3. **Given** the reordered workout C, A, B has been left and reopened, **when** the active workout is rendered again, **then** it still displays C, A, B.
4. **Given** normal mode or Large Mode on an iPhone 16 Simulator, **when** the user enters edit mode, **then** the move controls remain operable and VoiceOver identifies them as exercise-move controls.

### Edge Cases

- Moving the first section to the end and the last section to the beginning preserves all exercises exactly once.
- A completed move always normalizes every affected `WorkoutExercise.order` to a zero-based contiguous sequence, even if the pre-move values contain gaps.
- Empty and single-exercise workouts remain stable; no set or sub-set row becomes independently movable.
- Leaving edit mode without completing a drag does not change the stored order.

## Requirements

### Functional Requirements

- **FR-001**: Edit mode MUST expose one discoverable move entry point for each whole exercise section when at least two exercises are present.
- **FR-002**: A completed cross-section move MUST update the rendered section order in the same interaction.
- **FR-003**: A completed move MUST persist a zero-based contiguous `WorkoutExercise.order` sequence with no duplicate or skipped values.
- **FR-004**: Reopening the same workout MUST reconstruct the last completed exercise order.
- **FR-005**: One XCUITest MUST launch the authorized DEBUG fixture, render the production `ActiveWorkoutView`, perform the actual whole-section C-before-A drag, and fail behaviorally before the production interaction repair.
- **FR-006**: A separate app unit test MUST invoke the production reorder/renumber seam, assert exact exercise identity and contiguous order, save, and refetch through a fresh context. This invariant test MUST NOT duplicate the production algorithm and is not the interaction RED.
- **FR-007**: Normal mode and Large Mode MUST retain a usable section-level move entry point, and VoiceOver MUST identify the control and its exercise context.
- **FR-008**: Existing set/sub-set editing and deletion behavior, exercise-template ordering, and exercise-picker ordering MUST remain unchanged.
- **FR-009**: The current MY-1706 policy-driven snackbar/FAB, keyboard, accessibility-focus, and single-root-animation behavior in `ActiveWorkoutView` MUST remain unchanged while the section-reorder path is repaired.

### Key Entities

- **Active workout**: The current strength-training session whose exercise collection is rendered and persisted.
- **Workout exercise**: One exercise section in the active workout. Its existing `order` value determines display and persistence ordering.
- **Exercise section**: The complete visual group for one workout exercise, including its set rows; it is the atomic move target for this feature.

## Scope Boundaries

### Files in scope

- `VitalStride/Sources/ActiveWorkoutView.swift`
- `VitalStride/Sources/VitalStrideApp.swift` (DEBUG-only, launch-argument-gated test entry/fixture)
- `VitalStrideTests/Sources/ExerciseManagementTests.swift`
- `VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift`
- `specs/023-active-workout-section-reorder-fix/**`

### Files NOT to touch

- `Packages/**`
- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift`
- Set/sub-set editing or deletion UI
- Exercise picker ordering and `WorkoutTemplate` / `TemplateExercise` ordering
- `VitalStride/Resources/Localizable.xcstrings`
- `project.yml` and generated `VitalStride.xcodeproj/**`
- macOS, watchOS, widget, and prototype targets
- Any normal Debug or Release behavior in `VitalStrideApp.swift`; the authorized harness is opt-in and DEBUG-only
- MY-1706's policy-driven snackbar/FAB, keyboard, accessibility-focus, and root-animation behavior inside `ActiveWorkoutView.swift`

### Public signatures

- No public API may be added or changed.
- An app-target internal, production-owned reorder seam may be extracted in `ActiveWorkoutView.swift` solely to make the move/renumber behavior testable; its final Swift signature is intentionally left to implementation and compiler validation.
- The test entry, deterministic fixture, and stable UI-test selectors are app-internal test surfaces available only to the authorized DEBUG flow; no Release entry or behavior may be added.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The three-exercise move from A, B, C to C, A, B succeeds in one edit interaction and renders immediately.
- **SC-002**: After every tested move, persisted order values are exactly the integer range `0..<exerciseCount`.
- **SC-003**: The reopened workout preserves the completed order in the automated persistence regression and simulator acceptance check.
- **SC-004**: On iPhone 16 Simulator in normal and Large Mode, every exercise section has an operable move control that VoiceOver identifies with exercise context.
- **SC-005**: With only the DEBUG harness and XCUITest added, the focused UI test fails because the unchanged whole-section interaction cannot complete; after the production repair it passes without changing the fixture or assertion intent.

## Assumptions & Dependencies

- The existing edit-mode entry remains the way users start and finish reordering; this feature does not redesign the toolbar.
- SwiftData remains the persistence mechanism for `WorkoutExercise.order`; no schema or migration is required.
- Owner decision `eb00fa65-5302-4150-99b4-d742c9b186aa` resolves the prior test-scope question in favor of the real XCUITest interaction RED.
- `VitalStrideUITests` is already a directory-backed target included by existing schemes, so the new test file requires no `project.yml` change.
- The required CI AppUI gate remains authoritative on its repository-declared simulator. MY-1473 additionally requires interactive iPhone 16 Simulator acceptance for normal/Large Mode and VoiceOver.
- There are no unresolved product, content, or authority decisions. MY-1486 is cancelled and its replacement MY-1706 is complete in the declared current base, so neither is an implementation blocker. Before implementation dispatch, Team Lead must confirm MY-1484's still-active shared AppUI/Xcode validation lane is quiescent and supply the sole Fullstack implementer with the verified repository, approved exact reviewed planning ref, scope, acceptance, and current dependency state. Fullstack then owns first delivery-workspace classification and, only for genuinely new state, checkout, verification, metadata persistence/read-back, and continuation in that same run. Existing, partial, or conflicting delivery state returns to Team Lead for recovery. The registered workspace remains bound to the four-path implementation allowlist and must be rechecked for later drift.
- The technical mechanism must stay inside AppUI and preserve the excluded UI and package boundaries above.

## Non-Goals

- Reordering set or sub-set rows.
- Reordering exercises in templates, pickers, or other workouts.
- Changing workout schemas, package APIs, toolbar layout, or unrelated exercise-section controls.
