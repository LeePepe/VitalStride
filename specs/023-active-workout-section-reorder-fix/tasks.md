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

- [ ] T001 [US1] Complete the remaining title-preserving section-reorder composition in `VitalStride/Sources/ActiveWorkoutView.swift`, using the published fixture, tests, and production ordering seam as fixed inputs

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `AppUI` |
| Layer context | `VitalStride/CONTEXT.md`; repository terminology in `CONTEXT.md`; constitution quality bars in `.specify/memory/constitution.md` |
| Vertical slice | `US1` — Reorder whole exercise sections |
| Internal task edges | None; one mergeable AppUI slice |
| Dispatch blockers | The exhausted repair budget remains exhausted. AI Reviewer must PASS this exact planning revision, then Team Lead must explicitly authorize any later Fullstack execution. |
| Files in scope | `VitalStride/Sources/ActiveWorkoutView.swift` only for a later explicitly authorized implementation; `specs/023-active-workout-section-reorder-fix/**` for this planning revision |
| Interface impact | Internal-only. No public API change. Preserve the published production reorder seam, DEBUG fixture, and stable selectors; repair only the `ActiveWorkoutView.swift` title/content-plus-control composition. |
| Contract pointer | `contracts/exercise-section-reorder.md` |
| Exact workdir | Reuse MY-1812's registered `delivery_work_dir`; preserve its uncommitted candidate and do not create a replacement checkout |
| Required CI | AppUI gate declared by `VitalStride/CONTEXT.md` on iPhone 17 Simulator |

#### Files NOT to touch

- `Packages/**`
- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStride/Sources/VitalStrideApp.swift`
- `VitalStrideTests/Sources/ExerciseManagementTests.swift`
- `VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift`
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

1. **Fixed baseline**: Reuse PR #448 head `db43fab774b06ef887add8014b3c2470ff396c8d`, its DEBUG fixture, production ordering seam, handle/end-target identifiers, unit invariant, and test blob `7738a0c270a884510fe88755aedef7605a0b53a1`. Do not edit those verification surfaces.
2. **Composition repair**: In `ActiveWorkoutView.exerciseList`, retain one title/content-bearing `ActiveExerciseSection` composition per outer `WorkoutExercise` in edit mode and attach its distinct move control/drop behavior to that same returned composition. Do not emit a sibling handle `Section` or a handles-only edit branch.
3. **Title/control interface**: Keep the localized exercise title independently queryable as `StaticText`; retain the existing handle identifier, exact localized label, drag/adjustable semantics, and at-least-44pt target. Retain the separate terminal target after the last exercise.
4. **Unchanged-test proof**: Run both existing `ActiveWorkoutSectionReorderUITests` together without any test diff. They must prove C-before-A immediate/reopen/Large Mode behavior and A-to-terminal B/C/A behavior.
5. Normalize the completed sequence to zero-based contiguous values and publish the mutations immediately. Invalid, cancelled, empty, single-item, and no-op moves remain stable.
6. Use each exercise's existing localized display text and system drag/move or adjustable semantics for accessibility. Do not add a hard-coded visible/a11y string or edit the localization catalog.
7. If implementation adds an explicit save, handle failure without forced failure/casts, silent swallowing, or logs containing workout/health values.
8. Keep MY-1706's current `ActiveWorkoutView.body` policy consumption and animation ownership intact; reorder-specific changes must not move, duplicate, or bypass that composition.

#### Successor recovery acceptance

- **SR-AC-01 — title identity**: Before edit mode, during edit mode, and after each tested drag, `Exercise A/B/C` remain resolvable by the existing `StaticText` queries; no query resolves through the move control as `Other`.
- **SR-AC-02 — one exercise composition**: Each sorted `WorkoutExercise` has one title/content-bearing composition containing its existing set/sub-set UI plus one distinct edit-only move control; no sibling top-level handle section and no handles-only branch exists.
- **SR-AC-03 — control identity**: Every handle retains `ActiveWorkoutExerciseMoveHandle_<nameEn>`, the exact localized exercise label, drag/adjustable semantics, and a target at least 44×44 points; `ActiveWorkoutExerciseEndDropTarget` remains independently discoverable.
- **SR-AC-04 — unchanged interaction coverage**: The first published test proves immediate C/A/B, reopened C/A/B, and Large Mode B-before-C; the second proves terminal B/C/A. Both tests execute together without source changes.
- **SR-AC-05 — scope and compatibility**: The implementation diff is only `VitalStride/Sources/ActiveWorkoutView.swift`; test blob `7738a0c270a884510fe88755aedef7605a0b53a1`, `ActiveExerciseSection.swift`, toolbar behavior, set/sub-set behavior, and MY-1706 composition remain unchanged.
- **SR-AC-06 — manual evidence**: On iPhone 17 Simulator, capture normal and Large Mode edit-state evidence showing each localized title, existing set content, and its separate move control simultaneously; with VoiceOver, record focus output identifying the exercise control without hiding the title.
- **SR-AC-07 — authority**: A passing planning verdict and Team Lead's later explicit execution authorization both exist before Fullstack resumes. This revision does not reset the exhausted repair budget.

#### Task-local functional acceptance

- **AC-1**: The published fixture/tests, production seam, handle/end-target identities, and accepted historical RED remain unchanged at the implementation base.
- **AC-2**: After the successor repair, with A/B/C in edit mode, each title/content-bearing exercise composition—not its set rows—has a discoverable separate move entry point; the fixed tests move C before A and observe C/A/B immediately and after leaving/re-entering the workout.
- **AC-3**: The production reorder seam leaves every exercise present exactly once and rewrites order values to exactly 0/1/2 for the three-exercise unit invariant.
- **AC-4**: After save and fresh-context refetch, the unit invariant still observes C/A/B with contiguous values.
- **AC-5**: On iPhone 16 Simulator, the move entry point works in normal and Large Mode; VoiceOver identifies the exercise and exposes system movement semantics.
- **AC-6**: The DEBUG harness is opt-in, changes no ordinary Debug or Release behavior, uses stable selectors only for the test flow, and preserves the existing ExercisePicker/snackbar harness flag semantics.
- **AC-7**: Set/sub-set edit and delete behavior, template/picker ordering, package code, localization, project configuration, historical spec 017, and MY-1706's policy-driven snackbar/FAB, keyboard, accessibility-focus, and root-animation behavior are unchanged.

#### Exact verification

```bash
# From the VitalStride repository root.

# Focused successor gate: both fixed reorder tests together.
xcodegen generate --quiet && xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideUITests/ActiveWorkoutSectionReorderUITests \
  -resultBundlePath ../successor-reorder/reorder-tests.xcresult

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

# The fixed test surface must keep its published blob identity.
git hash-object VitalStrideUITests/Sources/ActiveWorkoutSectionReorderUITests.swift
```

Required CI then runs the current AppUI layer command from `VitalStride/CONTEXT.md` on iPhone 17 Simulator.

#### Interactive acceptance evidence

- iPhone 17 Simulator, normal mode: enter Edit, confirm every existing title and set row remains visible beside its separate move control, move the third exercise before the first, and confirm immediate order.
- Leave and reopen the workout, then confirm persisted order and no duplicate/gapped values.
- Repeat control use in Large Mode.
- With VoiceOver enabled, focus every move entry point and confirm it identifies the corresponding exercise and offers system movement semantics.
- Confirm individual set/sub-set rows did not gain move controls and their existing edit/delete interactions still work.

**Checkpoint**: US1 is ready for Team Lead acceptance only after both fixed reorder tests pass together, the manual title/control coexistence evidence is attached, and the implementation diff contains only `VitalStride/Sources/ActiveWorkoutView.swift`.

## Dependencies & Execution Order

- `T001` has no internal upstream task and no parallel sibling.
- MY-1486 is cancelled; completed successor MY-1706 is part of the compatibility baseline, not a pending task edge.
- MY-1812 already has a registered Fullstack workspace, published PR, and preserved dirty candidate. A later authorized executor must reuse them exactly; no new checkout, reset, clean, test edit, or replacement candidate is allowed.
- The published fixture, tests, ordering seam, and failure result are fixed inputs. The remaining source repair precedes the focused unchanged-test run, manual accessibility evidence, and full AppUI verification.
- No cross-layer edge exists. `Packages/**` remains excluded.
- AI Reviewer PASS makes the successor plan ready; it does not authorize implementation or reset the exhausted repair budget. Team Lead must explicitly authorize any later Fullstack execution.

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
| Existing set/sub-set/template/picker behavior unchanged (FR-008) | US1 / T001 AC-7 plus one-file scope audit |
| MY-1706 current-base behavior unchanged (FR-009) | US1 / T001 AC-7 plus focused/full AppUI verification |
| Title remains `StaticText` during edit/reorder (FR-010) | US1 / T001 SR-AC-01, SR-AC-04 |
| One title/content + move-control composition (FR-011) | US1 / T001 SR-AC-02, SR-AC-03 |
| Both published tests unchanged and passing (FR-012) | US1 / T001 SR-AC-04, SR-AC-05 |
