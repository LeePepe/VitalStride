# Feature Specification: Active Workout Exercise Section Reorder Fix

**Feature Branch**: `023-active-workout-section-reorder-fix`

**Created**: 2026-08-25

**Revised**: 2026-10-15 — successor recovery contract for PR #448 at `db43fab774b06ef887add8014b3c2470ff396c8d`

**Status**: Review candidate

**Input**: MY-1473 and accepted Spec 023 revision `bb13c2f3fea7067763cfa9966a751cef29a1beba`; Owner decision `eb00fa65-5302-4150-99b4-d742c9b186aa`; PR #448 published head `db43fab774b06ef887add8014b3c2470ff396c8d`; and MY-1812's exhausted structural-recovery evidence. The published harness, ordering seam, identifiers, terminal target, and two reorder tests are fixed inputs. This successor revision plans only the remaining title/control composition repair.

**Constitution refs**: Core Principles II/III/VII; Cross-Cutting Quality Bars A/C/D/E/G/H/I; Planning Review / Dual-Approval Gate

## Existing Behaviour

- `ActiveWorkoutView` shows `EditButton` when the active workout has more than one exercise.
- `exerciseList` sorts existing `WorkoutExercise` values by `order`, renders one `ActiveExerciseSection` per exercise, and attaches `.onMove` to the outer `ForEach`; `moveExercises(from:to:)` moves the sorted values and rewrites contiguous order values.
- The shipped `ExerciseManagementTests.reorderExercises` copies the movement and renumbering algorithm in test code. It proves those copied mutations, not that the production whole-section interaction can start or complete.
- `VitalStrideApp.swift` already contains unrelated, launch-argument-gated DEBUG UI-test harnesses, and `project.yml` already discovers `VitalStrideUITests/Sources/**`; no target configuration change is needed.
- MY-1706 changed the same source file above `exerciseList`: current `body` derives `ActiveWorkoutSnackbarLayout.policy`, keeps a stable policy-driven header/bottom safe-area composition, and gives root geometry animation ownership to `.activeWorkoutRootAnimation(policy:)`. The reorder symbols and behavior above are unchanged from the prior planning reference.
- PR #448 currently publishes the accepted fixture, production ordering seam, move-handle identifiers, terminal target, and two `ActiveWorkoutSectionReorderUITests` at exact head `db43fab774b06ef887add8014b3c2470ff396c8d`. The tests query `Exercise A/B/C` as `StaticText` before and during edit-mode order assertions.
- The final authorized structural recovery proved handle and terminal-target discovery, then both unchanged tests failed because an edit-only handles tree exposed exercise titles as accessibility `Other` rather than the existing title `StaticText`. The preserved result is `structural-final/reorder-tests.xcresult`; the published head and tests did not change.

## Compatibility

- Preserve the current MY-1706 snackbar/FAB placement, keyboard-state composition, `@MainActor` animation policy, accessibility focus routing, and single root animation ownership in `ActiveWorkoutView.body`.
- Preserve existing `ActiveExerciseSection` internals, set/sub-set edit and delete behavior, localized exercise text, template/picker ordering, ordinary Debug/Release startup, and all public/package/schema contracts.
- The authorized DEBUG fixture remains opt-in and isolated. Its dedicated launch argument must select deterministic isolated storage and suppress ordinary exercise-catalog seeding without changing the existing ExercisePicker flag/container path or snackbar harness. With all test arguments absent, current app startup behaves exactly as before.
- In edit mode, each exercise's existing localized title remains visible and independently queryable as `StaticText`; its matching move control remains a separate at-least-44pt accessibility element with the existing identifier and localized exercise label. The title element and move control coexist and reorder as one `WorkoutExercise` composition unit.
- Preserve both published reorder tests byte-for-byte. Changing title queries to generic section identities, `.any`, or the move control's label is not authorized by this successor revision.

## Removed Behaviour

- Replace only the unreliable assumption that native row `.onMove` can expose a usable move entry for a `ForEach` whose rendered children are whole SwiftUI sections.
- No existing test is removed or weakened. The published production-seam unit invariant and its save/fresh-context proof remain fixed verification inputs.
- No MY-1706 behavior, set/sub-set behavior, toolbar behavior, localization, package code, project configuration, or companion-target behavior is removed. The authority for the interaction/test-surface change is Owner decision `eb00fa65-5302-4150-99b4-d742c9b186aa`.
- The published two-sibling-section shape and the preserved handles-only edit branch are removed as acceptable composition strategies: the former does not expose move handles, while the latter removes the title/content section from the edit accessibility tree. This does not authorize removing title content, changing its query identity, or editing the tests.

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
5. **Given** A, B, C are visible before edit mode, **when** the user enters edit mode and completes either C-before-A or A-to-terminal, **then** all three localized titles remain independently queryable as title text while their distinct move controls remain discoverable.

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
- **FR-010**: Edit mode MUST keep every exercise's existing localized title visible and independently queryable as `StaticText` before and after a completed move; a move-control accessibility label MUST NOT substitute for that title element.
- **FR-011**: Each sorted `WorkoutExercise` MUST render as one title/content-bearing composition unit that also exposes exactly one distinct section-level move control. The implementation MUST NOT emit sibling top-level sections for one exercise or switch to a handles-only edit tree.
- **FR-012**: Both published `ActiveWorkoutSectionReorderUITests` MUST remain byte-for-byte unchanged and pass together, including C-before-A immediate/reopen/Large Mode coverage and A-to-terminal B/C/A coverage.

### Key Entities

- **Active workout**: The current strength-training session whose exercise collection is rendered and persisted.
- **Workout exercise**: One exercise section in the active workout. Its existing `order` value determines display and persistence ordering.
- **Exercise section**: The complete visual group for one workout exercise, including its set rows; it is the atomic move target for this feature.

## Scope Boundaries

### Files in scope

- `VitalStride/Sources/ActiveWorkoutView.swift`
- `specs/023-active-workout-section-reorder-fix/**`

The existing DEBUG fixture and test files at published head `db43fab774b06ef887add8014b3c2470ff396c8d` are fixed verification surfaces for the successor repair, not editable implementation scope.

### Files NOT to touch

- `Packages/**`
- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStride/Sources/VitalStrideApp.swift`
- `VitalStrideTests/Sources/ExerciseManagementTests.swift`
- `VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift`
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
- The published test entry, deterministic fixture, and stable UI-test selectors remain app-internal test surfaces available only to the authorized DEBUG flow; no Release entry or behavior may be added.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The three-exercise move from A, B, C to C, A, B succeeds in one edit interaction and renders immediately.
- **SC-002**: After every tested move, persisted order values are exactly the integer range `0..<exerciseCount`.
- **SC-003**: The reopened workout preserves the completed order in the automated persistence regression and simulator acceptance check.
- **SC-004**: On iPhone 16 Simulator in normal and Large Mode, every exercise section has an operable move control that VoiceOver identifies with exercise context.
- **SC-005**: The published interaction RED remains the accepted pre-repair evidence; after the successor repair, both fixed XCUITests pass without changing the fixture, test source, or assertion intent.
- **SC-006**: During edit mode and after each tested drag, `Exercise A/B/C` remain resolvable through the tests' existing `StaticText` queries while the matching move handles retain their identifiers, exact localized labels, and at-least-44pt targets.
- **SC-007**: One focused run executes both existing reorder tests with zero failures and no diff to their published blob `7738a0c270a884510fe88755aedef7605a0b53a1`.

## Assumptions & Dependencies

- The existing edit-mode entry remains the way users start and finish reordering; this feature does not redesign the toolbar.
- SwiftData remains the persistence mechanism for `WorkoutExercise.order`; no schema or migration is required.
- Owner decision `eb00fa65-5302-4150-99b4-d742c9b186aa` resolves the prior test-scope question in favor of the real XCUITest interaction RED.
- `VitalStrideUITests` is already a directory-backed target included by existing schemes; the published reorder-test file requires no `project.yml` change and remains unchanged.
- The required CI AppUI gate remains authoritative on its repository-declared simulator. MY-1473 additionally requires interactive iPhone 16 Simulator acceptance for normal/Large Mode and VoiceOver.
- There are no unresolved product, content, or authority decisions. MY-1812 already has a registered Fullstack workspace, PR #448, and a preserved uncommitted candidate; any later authorized implementation must reuse that state without checkout, reset, clean, or test changes. Team Lead retains scheduling and must explicitly authorize execution after the successor planning revision passes review.
- The technical mechanism must stay inside AppUI and preserve the excluded UI and package boundaries above.
- The exhausted structural-recovery budget is not reset by this planning revision. A passing spec gate is readiness evidence only; Team Lead must separately authorize any later Fullstack execution.

## Non-Goals

- Reordering set or sub-set rows.
- Reordering exercises in templates, pickers, or other workouts.
- Changing workout schemas, package APIs, toolbar layout, or unrelated exercise-section controls.
- Changing either existing reorder test, replacing title queries with section identities, or treating a handle label as equivalent title content.
