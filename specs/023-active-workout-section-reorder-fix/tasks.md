---
description: "Layer-scoped task graph for MY-1473"
---

# Tasks: Active Workout Exercise Section Reorder Fix

**Input**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/exercise-section-reorder.md`, and `quickstart.md` in this directory

**Organization**: One vertical user story and one formal AppUI implementation task. DEBUG harness, behavioral XCUITest RED, source repair, unit persistence invariant, and interactive accessibility acceptance stay together so the red-green slice is independently schedulable and mergeable.

## Format: `[ID] [P?] [Story] Description`

- `[P]` is omitted because this task has no safe parallel sibling.
- `[US1]` maps directly to the sole user story in `spec.md`.
- The executable row names every implementation path.

## Phase 1: User Story 1 — Reorder whole exercise sections (P1)

**Goal**: A user can move a complete exercise section during edit mode, see the new order immediately, and reopen the workout with the same contiguous persisted order.

**Independent Test**: Launch the DEBUG fixture with three exercises, use XCUITest to perform the actual C-before-A whole-section drag and observe C/A/B before and after re-entry, verify contiguous values through a production-seam save/fresh-context unit invariant, then exercise normal/Large Mode and VoiceOver on iPhone 16 Simulator.

- [ ] T001 [US1] Deliver the test-first AppUI section-reorder fix in `VitalStride/Sources/VitalStrideApp.swift`, `VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift`, `VitalStride/Sources/ActiveWorkoutView.swift`, and `VitalStrideTests/Sources/ExerciseManagementTests.swift`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `AppUI` |
| Layer context | `VitalStride/CONTEXT.md`; repository terminology in `CONTEXT.md`; constitution quality bars in `.specify/memory/constitution.md` |
| Vertical slice | `US1` — Reorder whole exercise sections |
| Internal task edges | None; one mergeable AppUI slice |
| Dispatch blockers | MY-1486 is cancelled and successor MY-1706 is complete in current `main`; preserve that current-base behavior. Team Lead must make MY-1484's still-active shared AppUI/Xcode validation lane quiescent, provision the reviewed planning revision as MY-1567's delivery base, and recheck this allowlist for later drift before dispatch/build. |
| Files in scope | `VitalStride/Sources/ActiveWorkoutView.swift`; `VitalStride/Sources/VitalStrideApp.swift` (DEBUG-only harness); `VitalStrideTests/Sources/ExerciseManagementTests.swift`; `VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift` |
| Interface impact | Internal-only. No public API change. One production-owned app-internal reorder/renumber seam may be extracted in `ActiveWorkoutView.swift`; one launch-argument-gated DEBUG test entry/fixture and stable outer-exercise selectors may be added. Implementation owns final Swift signatures. |
| Contract pointer | `contracts/exercise-section-reorder.md` |
| Exact workdir | VitalStride repository root |
| Required CI | AppUI gate declared by `VitalStride/CONTEXT.md` on iPhone 17 Simulator |

#### Files NOT to touch

- `Packages/**`
- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift`
- Set/sub-set editing, deletion, or reordering UI
- Exercise-picker ordering and `WorkoutTemplate` / `TemplateExercise` ordering
- `VitalStride/Resources/Localizable.xcstrings`
- `project.yml` and `VitalStride.xcodeproj/**`
- `VitalStrideMac/**`, `VitalStrideWatch Watch App/**`, `VitalStrideWidgets/**`, `Prototype/**`
- Any normal Debug or Release behavior in `VitalStrideApp.swift`
- MY-1706's policy-driven snackbar/FAB placement, keyboard-state composition, accessibility focus routing, `@MainActor` animation policy, or single root animation ownership in `ActiveWorkoutView.swift`
- Historical `specs/017-active-workout-reorder-affordance/**`

#### Execution contract

1. **RED setup**: Add the launch-argument-gated DEBUG fixture/entry and the one XCUITest without repairing reorder behavior. The dedicated reorder flag uses isolated storage, suppresses ordinary exercise-catalog seeding, seeds three distinguishable exercises, and hosts the production `ActiveWorkoutView`; it must not change the existing ExercisePicker flag/container path or snackbar harness.
2. **RED evidence**: Run the focused XCUITest and capture failure at the actual whole-section drag or immediate C/A/B assertion. Compilation, missing fixture setup, or a missing seam is not RED evidence.
3. **GREEN**: In `ActiveWorkoutView.exerciseList`, expose one edit-mode move entry point for each outer `WorkoutExercise` section. Route drag completion through the production reorder seam and preserve `ActiveExerciseSection` internals. Rerun the unchanged-intent XCUITest to observe immediate and re-entered C/A/B.
4. **Unit invariant**: Replace or extend the existing reorder test so it invokes the production seam, moves A/B/C to C/A/B, asserts exact identity and 0/1/2, saves, and refetches from a fresh `ModelContext`. Do not duplicate collection movement or order assignment, and do not report this unit test as the interaction RED.
5. Normalize the completed sequence to zero-based contiguous values and publish the mutations immediately. Invalid, cancelled, empty, single-item, and no-op moves remain stable.
6. Use each exercise's existing localized display text and system drag/move or adjustable semantics for accessibility. Do not add a hard-coded visible/a11y string or edit the localization catalog.
7. If implementation adds an explicit save, handle failure without forced failure/casts, silent swallowing, or logs containing workout/health values.
8. Keep MY-1706's current `ActiveWorkoutView.body` policy consumption and animation ownership intact; reorder-specific changes must not move, duplicate, or bypass that composition.

#### Task-local functional acceptance

- **AC-1**: After only the DEBUG harness and XCUITest are added, the focused test builds/launches and fails because the unchanged production whole-section interaction cannot complete or render C/A/B.
- **AC-2**: After GREEN, with A/B/C in edit mode, each whole section—not its set rows—has a discoverable move entry point; the same XCUITest moves C before A and observes C/A/B immediately and after leaving/re-entering the workout.
- **AC-3**: The production reorder seam leaves every exercise present exactly once and rewrites order values to exactly 0/1/2 for the three-exercise unit invariant.
- **AC-4**: After save and fresh-context refetch, the unit invariant still observes C/A/B with contiguous values.
- **AC-5**: On iPhone 16 Simulator, the move entry point works in normal and Large Mode; VoiceOver identifies the exercise and exposes system movement semantics.
- **AC-6**: The DEBUG harness is opt-in, changes no ordinary Debug or Release behavior, uses stable selectors only for the test flow, and preserves the existing ExercisePicker/snackbar harness flag semantics.
- **AC-7**: Set/sub-set edit and delete behavior, template/picker ordering, package code, localization, project configuration, historical spec 017, and MY-1706's policy-driven snackbar/FAB, keyboard, accessibility-focus, and root-animation behavior are unchanged.

#### Exact verification

```bash
# From the VitalStride repository root.

# True behavioral RED/GREEN first.
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStrideUITests \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideUITests/ActiveWorkoutSectionReorderUITests

# Ordering/persistence invariant (not the interaction RED).
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ExerciseManagementTests

# Full task-local AppUI regression required by MY-1473.
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

# Scope audit: implementation paths only. Planning artifacts may already be
# present at the reviewed revision but Fullstack must not edit them.
git diff --name-only "$DELIVERY_BASE_SHA"...HEAD
```

Required CI then runs the current AppUI layer command from `VitalStride/CONTEXT.md` on iPhone 17 Simulator.

#### Interactive acceptance evidence

- iPhone 16 Simulator, normal mode: enter Edit, move the third exercise before the first, confirm immediate order.
- Leave and reopen the workout, then confirm persisted order and no duplicate/gapped values.
- Repeat control use in Large Mode.
- With VoiceOver enabled, focus every move entry point and confirm it identifies the corresponding exercise and offers system movement semantics.
- Confirm individual set/sub-set rows did not gain move controls and their existing edit/delete interactions still work.

**Checkpoint**: US1 is ready for Team Lead acceptance when behavioral RED/GREEN evidence, automated verification, and interactive evidence are attached to the implementation handoff, and the diff respects the four-file implementation allowlist.

## Dependencies & Execution Order

- `T001` has no internal upstream task and no parallel sibling.
- MY-1486 is cancelled; completed successor MY-1706 is part of the current base and contributes a compatibility constraint, not a pending task edge.
- Before dispatch, Team Lead must make MY-1484's `in_review` AppUI/Xcode validation lane quiescent, then provision the authoritative MY-1567 delivery workspace/base at this reviewed planning revision.
- Within `T001`, DEBUG harness/test setup precedes behavioral RED capture; RED precedes GREEN; GREEN precedes the unit invariant and full automated/interactive verification.
- No cross-layer edge exists. `Packages/**` remains excluded.
- Team Lead dispatches implementation only after the exact planning revision receives AI Reviewer PASS and Team Lead approval.

## Acceptance Traceability

| Spec acceptance | Slice/task evidence |
|---|---|
| Pre-fix behavioral RED (FR-005) | US1 / T001 AC-1 focused XCUITest |
| Section-level move entry points (FR-001) | US1 / T001 AC-2 and interactive acceptance |
| Immediate/re-entered C/A/B rendering (FR-002, FR-004) | US1 / T001 AC-2 focused XCUITest |
| Contiguous order values (FR-003) | US1 / T001 AC-3 unit invariant |
| Production seam + save/fresh-context persistence (FR-006) | US1 / T001 AC-3 and AC-4 unit invariant |
| Normal/Large Mode and VoiceOver (FR-007) | US1 / T001 AC-5 interactive evidence |
| DEBUG-only/no Release effect (FR-005 compatibility surface) | US1 / T001 AC-6 |
| Existing set/sub-set/template/picker behavior unchanged (FR-008) | US1 / T001 AC-7 plus four-file scope audit |
| MY-1706 current-base behavior unchanged (FR-009) | US1 / T001 AC-7 plus focused/full AppUI verification |
