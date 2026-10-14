# Tasks: Reliable Editable Sub-Set Rows

**Input**: Design documents from `specs/026-reliable-editable-subset-rows/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/row-and-deletion-contract.md`, `quickstart.md`

**Source authority**: Owner-delegated Lead decision `01a138db-f9f3-7bb0-b4da-f8820e91559d`, effective 2026-10-14

**Planning base**: `main` `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`; the eventual reviewed planning revision descends directly from this SHA

**Constitution references**: Principles II, III, IV, VI and VII; Development Workflow / Planning Review; Cross-Cutting Quality Bars A, G, H, I and K

**Organization**: Exactly one US1 vertical product slice and one executable task. There is no renamed repair task, separate verification task, or inherited MY-1484 repair budget.

## Phase 1: User Story 1 — Edit and reliably remove any active-workout set row (P1)

**Goal**: Standard/working, pyramid, and drop-set rows use one actual editable production composition; actual menu-delete and committed full swipe traverse one reliable request seam; real refusal, confirmation, undo, accessibility, localization, geometry, and compatibility behavior are proven.

**Independent Test**: Launch the DEBUG acceptance mode that hosts the real production `ActiveExerciseSection` with adjacent standard/working, pyramid, and drop-set rows. Exercise real fields/menu/completion/copy; delete pyramid through the actual menu and drop-set through an actual committed full swipe; observe one request and real-seam traversal each; verify success/refusal/confirmation/undo; and measure the actual adjacent action-menu-trigger frames.

- [ ] T001 [US1] Write RED acceptance first, then deliver and verify the shared editable row plus real deletion request module across the exact AppUI allowlist in `VitalStride/Sources/ActiveWorkout/SetRow.swift`, `VitalStride/Sources/ActiveWorkout/SubSetRow.swift`, `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`, new `VitalStride/Sources/ActiveWorkout/SetDeletionRequest.swift`, `VitalStride/Sources/VitalStrideApp.swift`, focused `VitalStrideTests/Sources/` files, and new `VitalStrideUITests/Sources/SubSetProductionRouteUITests.swift`

### T001 Definition of Ready

| Field | Contract |
|---|---|
| Owning layer | `AppUI`; layer `depends_on: [VitalModels, HealthKitService, AIService, VitalUI, TelemetryKit, DesignKit]`; layer `depended_by: []`; task graph has no blocking task |
| Vertical slice | US1 — shared editable pyramid/drop-set rows and reliable production deletion |
| Context pointers | `VitalStride/CONTEXT.md`; repository `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`; constitution; all reviewed `specs/026-reliable-editable-subset-rows/**` artifacts |
| Planning/base identity | Implementation starts from the exact reviewed planning revision, which descends directly from `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`; stopped candidate `bf66f046a810a368f317e386d7c0504ba41cf2c0` is negative evidence only |
| FS editable production files | `VitalStride/Sources/ActiveWorkout/SetRow.swift`; `VitalStride/Sources/ActiveWorkout/SubSetRow.swift`; `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`; new `VitalStride/Sources/ActiveWorkout/SetDeletionRequest.swift`; `VitalStride/Sources/VitalStrideApp.swift` only for the DEBUG production host/observation surface |
| FS editable test files | `VitalStrideTests/Sources/SubSetDeletionUndoTests.swift`; delete `VitalStrideTests/Sources/SubSetReadOnlyTests.swift` after retaining its valid compatibility assertions; new `VitalStrideTests/Sources/SharedEditableSetRowTests.swift`; `VitalStrideTests/Sources/ActiveExerciseRowContextsTests.swift`; `VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift`; new `VitalStrideUITests/Sources/SubSetProductionRouteUITests.swift` |
| Immutable inherited PR scope | `specs/026-reliable-editable-subset-rows/**` at `delivery_base_sha`; Fullstack verifies byte identity and does not edit it |
| Files NOT to touch | `Packages/**`; `VitalStride/Sources/ActiveWorkout/SetDeletionPolicy.swift`; `SetDeletionFocusTarget.swift`; `SetDeletionUndoController.swift`; `VitalStride/Sources/ActiveWorkoutView.swift`; `VitalStride/Sources/WorkoutNumericKeyboard.swift`; `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`; `VitalStride/Resources/Localizable.xcstrings`; `project.yml`; `VitalStride.xcodeproj/**`; companion/widget targets; all other app/test/spec paths; stopped MY-1484 state and Draft PR #422 |
| Public interface | None. Any row identity/configuration, request result/module, route observation, and DEBUG host remain app-internal; no package/public API or new dependency |
| Production ownership | `SetRow` is the one actual weight/reps/menu/completion composition. Row configuration keeps child history/add-child actions and non-child SetType choices off while retaining pyramid/drop-set subtype/RPE/unilateral/copy behavior. The new request module alone owns policy dispatch, package-manager execution, and success-only undo/announcement/callback effects; the view only applies returned confirmation/focus data |
| Test ownership | XCUITest activates the real production menu and full-swipe configuration in `ActiveExerciseSection`. An observation-only decorator may wrap/delegate to the real request module; it cannot invoke, replace, or duplicate deletion |
| Removed behavior | Read-only pyramid/drop-set fields, tree-line/terminal-child presentation state, and sub-set-only delete menu contract; obsolete read-only tests are replaced, not merely renamed |
| Compatibility | Existing package deletion rules, order, confirmation, refusal, undo, announcement, dead-parent protection, standard-row smart progression/previous hints, bilateral editing, keyboard/copy, completion, SetType/RPE menu behavior, generation, previews, and compact/Large layout remain green |
| Stable acceptance | AC-001 through AC-011 in `spec.md`, with the exact task probes below |
| Verification | All commands and simulator checks in `quickstart.md`, from repository root, without a successor-specific skip or quarantine change |
| Entry gates | Exact planning revision has AI Reviewer `PASS`/`PASS WITH FOLLOW-UP`; Team Lead accepts readiness and dispatches one Fullstack run; registered delivery workspace/base metadata matches the reviewed planning revision; no competing implementation/candidate exists |

### T001 Acceptance Probes

- **AC-001 — Actual menu route**: In the production section host, open the actual pyramid row menu and activate the real destructive entry. Observe exactly one section request, one delegated real-seam traversal, the pyramid identity, one real success callback, and deletion/undo state. Calling any captured/stored closure is a failure.
- **AC-002 — Actual full-swipe route**: On a fresh host, drag the actual drop-set row far enough for the trailing full-swipe action to commit. Observe the same exactly-once request/seam contract for the drop-set. Tapping a revealed action or test stand-in is a failure.
- **AC-003 — Success and undo**: Pyramid and drop-set requests each remove only the selected row, retain parent/siblings, record one pending undo and one success announcement, call the callback once, and restore exact values/relative order through the existing undo route.
- **AC-004 — Production-reachable refusal**: In a fresh production host with one main row and its sole child, activate the main row's actual menu-delete, accept the existing cascade confirmation, and observe the real `WorkoutSetManager` zero-row refusal. Both rows/order remain unchanged; a fresh undo controller has no pending item/announcement; callback count is zero; returned focus is absent. Directly calling the seam for a hidden single-row affordance fails route acceptance.
- **AC-005 — Return-only ownership**: A parent with hidden children returns confirmation data with no mutation/success effect. Confirmed execution uses the same request module. The module owns success effects and accepts no presentation setter; the section applies returned confirmation/focus once.
- **AC-006 — Actual adjacent geometry**: Query each simultaneously adjacent standard/working, pyramid, and drop-set production row's actual action-menu trigger by `active-workout.row.<stable-row-id>.action-menu` and compare its `XCUIElement.frame` in their shared coordinate space. Every width/height is at least 44; standard/pyramid and pyramid/drop-set intersections are empty. Opened destructive items are covered separately; swipe buttons, constants, whole-row proxies, separate hosts, context flags, and synthesized rectangles fail acceptance.
- **AC-007 — Cataloged production identity**: Query the actual destructive entries in English and Simplified Chinese. Their label/value use translated `删除` plus `第 %lld 组` and `SetType.displayName`; a child entry communicates delete intent, displayed parent number and current pyramid/drop-set type. The untranslated `第 %lld 组%@子组，%@` entry, detached helpers, derived localization keys and catalog edits fail acceptance.
- **AC-008 — Actual shared composition/action effects**: Use the actual production elements to edit child weight/reps, open the common delete/SetType/RPE menu, change RPE, switch pyramid/drop-set subtype without parent/sibling/order loss, toggle unilateral/completion, and run the current custom-keyboard copy action through the production section route. The child picker contains only pyramid/drop-set; add-pyramid/add-drop remain present and working for the standard row but are not offered for a child.
- **AC-009 — Deletion compatibility**: Existing parent cascade confirmation, selected-child isolation, minimum-one-row refusal, order reflow, consecutive announcement identity, undo arbitration/expiry/restoration, and dead-parent protection all remain green with `Packages/**` unchanged.
- **AC-010 — Row compatibility, query restraint and visual matrix**: Standard smart progression/previous hints, bilateral editing, SetType/RPE menu, add-pyramid/add-drop generation, keyboard layout/safe area, compact/Large layout, and four production previews remain available. An observation/probe proves rendering/interacting with child rows performs no history lookup or smart-progression tree walk. iPhone 17 normal-light, normal-dark, Large-light, and Large-dark captures each show adjacent standard/pyramid/drop-set rows with aligned unclipped fields/menu/completion.
- **AC-011 — Scope/interface**: Diff contains only editable implementation paths plus immutable planning inherited from `delivery_base_sha`; no public API, persistence/schema, `SetType`, package, catalog, keyboard, project configuration, companion, reorder, add-exercise, stopped-candidate, or Draft PR #422 change.

### T001 Exact Verification

From repository root:

```bash
xcodegen generate
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/SubSetDeletionUndoTests \
  -only-testing:VitalStrideTests/SharedEditableSetRowTests \
  -only-testing:VitalStrideTests/ActiveExerciseRowContextsTests \
  -only-testing:VitalStrideTests/ActiveWorkoutHitTargetTests \
  -only-testing:VitalStrideUITests/SubSetProductionRouteUITests

bash scripts/ci/run-app-target-tests.sh
python3 scripts/i18n_check_lproj_parity.py
# Discard only ephemeral XcodeGen output before candidate freeze.
git restore --source=HEAD -- VitalStride.xcodeproj
git diff --exit-code -- project.yml VitalStride.xcodeproj
test -n "${DELIVERY_BASE_SHA:?export the exact reviewed planning SHA from registered issue metadata}"
git diff --name-only "${DELIVERY_BASE_SHA}"
git diff --exit-code "${DELIVERY_BASE_SHA}" -- specs/026-reliable-editable-subset-rows
```

Manual/simulator evidence follows `quickstart.md` and records the four-state visual matrix plus real menu, committed full swipe, undo, refusal, confirmation, copy, catalog identity, and measured-frame outcomes.

**US1 checkpoint**: The one implementation candidate demonstrates all AC-001 through AC-011 together. Partial helper, callback, synthetic-layout, or separate-host evidence does not advance the task.

## Dependencies and Execution Order

```text
US1 / T001 RED -> implementation -> focused production acceptance -> full AppUI/catalog/scope gates -> visual record
```

- T001 is the only node and has no task dependency.
- No part is separately dispatchable because row composition, request ownership, and production acceptance share the same section boundary.
- Fullstack publishes the fixed candidate PR and requests independent exact-SHA review under repository ADR-0021; Team Lead retains scheduling.
- Any failed acceptance probe returns within T001's normal review budget; it does not revive MY-1484 or MY-1485.

## Acceptance Traceability

| Spec acceptance / requirements | Slice | Task | Primary evidence |
|---|---|---|---|
| AC-001; FR-003, FR-006 | US1 | T001 | XCUITest actual pyramid menu activation + request/seam/callback counters + model/undo state |
| AC-002; FR-003, FR-006 | US1 | T001 | XCUITest actual committed drop-set full swipe + same production route evidence |
| AC-003; FR-004, FR-005 | US1 | T001 | Focused request-module success/undo tests and XCUITest production outcomes |
| AC-004; FR-004, FR-005 | US1 | T001 | Actual parent menu + confirmation in one-parent/one-child host reaches real manager refusal with zero effects/focus |
| AC-005; FR-004 | US1 | T001 | Confirmation/focus return-result tests and section application probe |
| AC-006; FR-007 | US1 | T001 | Actual adjacent action-menu-trigger `XCUIElement.frame` dimensions/intersections in one host |
| AC-007; FR-008 | US1 | T001 | English/zh-Hans production destructive-entry label/value queries + catalog parity command |
| AC-008; FR-001, FR-002, FR-007 | US1 | T001 | Production-hosted field/menu/subtype/RPE/unilateral/completion/copy interactions and main-only add-action proof |
| AC-009; FR-005 | US1 | T001 | Existing/focused deletion, undo, announcement, and package compatibility suites |
| AC-010; FR-001, FR-007, FR-010 | US1 | T001 | Existing row/keyboard regressions, no-child-history-query probe, four previews, full gate, four simulator captures |
| AC-011; FR-009 | US1 | T001 | Exact diff allowlist, immutable planning check, full gates |

## Implementation Strategy

1. Capture failing focused acceptance before production edits, including real XCUITest activation and geometry.
2. Deepen the request module and shared row composition without altering package/presentation dependency seams.
3. Make the focused production acceptance green, then run the full AppUI/catalog/scope gates.
4. Record the four-state simulator and behavior evidence on the same fixed candidate.
5. Do not run Spec Kit implementation from this planning issue; Team Lead dispatches the one successor only after exact-revision planning approval.
