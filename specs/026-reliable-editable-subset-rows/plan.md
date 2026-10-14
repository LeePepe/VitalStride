# Implementation Plan: Reliable Editable Sub-Set Rows

**Branch**: `026-reliable-editable-subset-rows` | **Date**: 2026-10-14 | **Spec**: `specs/026-reliable-editable-subset-rows/spec.md`

**Input**: Owner-delegated stop/successor decision `01a138db-f9f3-7bb0-b4da-f8820e91559d`, current `main` `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`, and the feature specification in this directory.

## Summary

Deliver one AppUI-only successor that replaces the separate read-only pyramid/drop-set row tree with the standard editable weight/reps/menu/completion composition and routes every delete affordance through one app-internal request seam. The seam owns policy dispatch, package-manager execution, and success-only undo/announcement/callback effects while returning confirmation and focus presentation results to the view. Production-hosted XCUITests activate the real menu item and committed full swipe, observe exactly one section request and real-seam traversal, and measure actual adjacent production control frames. The stopped MY-1484 candidate and Draft PR #422 remain unchanged negative evidence.

## Technical Context

**Language/Version**: Swift 6.0 with strict concurrency

**Primary Dependencies**: AppUI's existing local-package edges to VitalModels, HealthKitService, AIService, VitalUI, TelemetryKit, and DesignKit; this slice directly uses SwiftUI, SwiftData, XCTest/XCUITest, VitalModels, VitalUI, and DesignKit

**Storage**: Existing SwiftData `ExerciseSet` and `WorkoutExercise` records; no schema or migration

**Testing**: Swift Testing in `VitalStrideTests`; XCTest/XCUITest in `VitalStrideUITests`; actual `XCUIElement.frame` geometry in one launched app coordinate space

**Target Platform**: iOS 18+; iPhone 17 Simulator

**Project Type**: XcodeGen-managed multi-target app; AppUI layer only

**Performance Goals**: Preserve the section's single O(n) row-context pass; add no per-row sorting, persistence fetch, or tree walk

**Constraints**: No public API, package edit, schema change, localization-catalog edit, project configuration edit, or numeric-keyboard change; all interactive targets remain at least 44 by 44 points

**Scale/Scope**: Three production row/section files, one proposed app-internal deletion module, the existing app DEBUG harness, focused AppUI tests, and one new XCUITest suite

## Constitution Check

### Before design

| Gate | Result | Evidence |
|---|---|---|
| Principle II — strict concurrency | PASS | The request seam and row identity remain app-internal and MainActor-bound where they touch SwiftData/UI state; no unsafe escape is needed. |
| Principle III — layer ownership | PASS | All editable implementation paths are AppUI-owned. `VitalModels` deletion behavior is a read-only dependency. |
| Principle IV — XcodeGen source of truth | PASS | `project.yml` remains the source of truth. `xcodegen generate` is required before local tests so new files enter explicit build phases; generated `VitalStride.xcodeproj/**` output is verification-only, restored before candidate freeze, and never committed. |
| Principle VI — catalog localization | PASS | Destructive identity is composed at the production entry from existing cataloged identity/type/delete strings; no derived interpolation key or catalog edit is allowed. |
| Principle VII — platform restraint | PASS | iOS production/UI-test behavior only; no macOS/watchOS-specific feature. |
| Quality Bar A — scope | PASS | One exact AppUI implementation allowlist is declared below and in `tasks.md`. |
| Quality Bars H/I/K | PASS | Actual hosted controls, real frames, production activation, full focused tests, and a simulator visual matrix are mandatory. |

### After design

PASS. The design introduces one deep app-internal request module and reuses one row composition. It does not reproduce package deletion rules, create a second production/test route, or add a public/cross-layer interface.

## Baseline and Negative Evidence

At `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`:

- `SetRow` owns editable weight/reps, the complete action menu, custom-keyboard actions, completion, smart progression, and previous-set hints.
- `SubSetRow` owns a separate read-only weight/reps tree, delete-only menu, duplicated completion control, and tree-line presentation.
- `ActiveExerciseSection` branches on `SetType.isSubSet`; its four production menu/swipe closures call private `requestDelete(_:)`.
- `requestDelete(_:)` selects `SetDeletionPolicy`; private `performDelete` snapshots, calls `WorkoutSetManager.deleteSet`, records undo/announcement, applies focus, and invokes `onSetDeleted` after success.
- `SetDeletionPolicy`, `SetDeletionFocusTarget`, and `SetDeletionUndoController` are existing AppUI dependencies. `WorkoutSetManager` and `WorkoutSetTree` are package-owned deletion authorities.
- Existing tests call policy, manager, undo, focus, or stored callbacks in isolation. They do not instantiate the production section, activate its actual menu/swipe affordances, or measure adjacent production action-menu-trigger frames.
- Existing hit-target tests prove a `44` token, not actual adjacent geometry. `SubSetReadOnlyTests` describes behavior that production already partly contradicts and the successor intentionally removes.

Accepted plan `77bfc0a778ed5b59463f91032e07e0a89da783c3`, review comments `d400e4e7-862e-469b-8d8e-830c410dd059` and `359e1aa5-d966-418d-b80d-bb894013473c`, budget return `01a1385e-2b9e-70a7-8462-68fd7a6f2b2d`, Draft PR #422, and candidate `bf66f046a810a368f317e386d7c0504ba41cf2c0` are failure evidence only. This plan neither inherits their implementation nor uses them as a base.

## Design Decisions

### D1 — One production row composition

`SetRow` remains the sole weight/reps/action-menu/completion composition. An immutable app-internal row identity/configuration supplies either standard-row numbering or pyramid/drop-set parent/type identity plus action/history capabilities. `SubSetRow` may remain only as a thin adapter; it must not retain a second field, menu, or completion tree. The read-only controls, tree connector, terminal-child styling, and sub-set-only menu contract are removed.

All three row kinds expose the same delete, SetType and RPE menu controls. The standard picker retains all existing choices; a child picker is constrained to pyramid/drop-set choices so it cannot promote/detach a child or split the consecutive child run. Pyramid/drop-set acceptance changes RPE and switches between those two child types while retaining parent, siblings and order. The same numeric keyboard implementation serves all editable fields: unilateral editing and copy remain enabled for sub-sets, while add-pyramid/add-drop stay main-row-only so a child cannot create a nested child. Standard-row add-pyramid/add-drop behavior remains unchanged.

Smart progression and previous-set hints remain enabled exactly as today for standard rows. A sub-set configuration supplies neither `exercise` nor `previousSet`; `SetRow` must guard on that configuration before `PreviousSetLookup` or any smart-progression traversal, so adapting a child adds no history query. The successor does not add a `SetType.standard` case; “standard row” means the existing non-sub-set/working-row product presentation.

### D2 — One real request seam with return-only presentation results

Add one app-internal deletion request module under `VitalStride/Sources/ActiveWorkout/`. The section's `requestDelete(_:)` delegates to it exactly once. The module begins before `SetDeletionPolicy` dispatch and owns:

1. immediate-versus-confirm policy selection;
2. confirmed/immediate production execution through `WorkoutSetManager.deleteSet`;
3. success-only undo record and announcement;
4. success-only deletion callback; and
5. computation of the existing focus target.

The module returns confirmation, success-with-focus, or refusal/no-change information. It receives no confirmation/focus state setters and never mutates view presentation state. `ActiveExerciseSection` applies returned confirmation/focus data exactly once. Package refusal returns no focus and produces no undo, announcement, or deletion callback.

`SetDeletionPolicy.swift`, `SetDeletionFocusTarget.swift`, `SetDeletionUndoController.swift`, `ActiveWorkoutView.swift`, and all package files remain unchanged dependencies.

### D3 — Production activation, not callback substitution

The DEBUG XCUITest harness in `VitalStrideApp.swift` launches an in-memory fixture and renders the actual production `ActiveExerciseSection` with adjacent standard/working, pyramid, and drop-set rows. It must not reconstruct the rows, copy their actions, expose a “delete now” test button, or call a stored row closure.

An observation-only counting probe/decorator wraps the same real app-internal request module used outside tests and delegates every request to it. The harness may publish request/seam/callback counts and selected-row identity as accessibility-readable evidence, but it may not decide policy, delete data, record undo, or supply a parallel execution path.

XCUITest must:

- open the actual pyramid row action menu and activate its real destructive item;
- perform a trailing drag on the actual drop-set row far enough for the production full-swipe action to commit, without tapping a revealed stand-in action;
- observe one `requestDelete` entry and one wrapped real-seam traversal per action, correct selected-row identity, and the real success/undo result; and
- never invoke a captured callback directly.

### D4 — Actual adjacent geometry and composition parity

The same production host exposes stable accessibility identifiers on the actual weight field, reps field, shared action-menu trigger, and completion control for each row. The menu trigger identifier is `active-workout.row.<stable-row-id>.action-menu`, where the stable row identity comes from the model/fixture rather than list position. XCUITest reads those actual trigger `XCUIElement.frame` values while all three rows are simultaneously adjacent in one app coordinate space. AC-001/AC-007 separately open and query the destructive entry; opened menu items are not the simultaneous geometry target.

Each actual action-menu-trigger frame must be at least 44 by 44 points. The standard/pyramid and pyramid/drop-set intersections must be empty. Separately hosted rows, swipe buttons, whole-row frames, constants, context booleans, hand-built proxy controls, and synthesized rectangles are non-acceptance evidence.

The test also proves actual composition parity by editing sub-set weight/reps fields, toggling completion, opening the complete production menu, changing RPE, switching pyramid/drop-set type without parent/sibling/order loss, and exercising the existing custom-keyboard unilateral/copy routes. It verifies add-pyramid/add-drop are absent for a sub-set and remain available for the standard row. Element-presence flags or helper-only assertions are insufficient.

### D5 — Catalog-backed production identity

The actual destructive entry uses the translated app-catalog values `删除` and `第 %lld 组` plus `SetType.displayName` from the VitalModels catalog. Its accessibility label/value as read together states delete intent, displayed set/parent number and current child type. The implementation composes already-localized fragments for display/accessibility and never passes the combined result back to `String(localized:)`; it does not use the untranslated combined entry `第 %lld 组%@子组，%@`. English and Simplified Chinese XCUITest cases query the production menu entry. A helper string detached from that entry does not satisfy acceptance, and both catalogs remain unchanged.

### D6 — Compatibility and verification stay in one vertical slice

The one task contains RED evidence, implementation, focused verification, full AppUI verification, and the four-state simulator review. The production refusal fixture contains one main row plus its sole child: the visible main-row menu returns cascade confirmation and confirmed execution reaches the real manager's zero-row refusal. Existing parent cascade, selected-child isolation, refusal, order reflow, announcement, undo, dead-parent protection, smart progression, keyboard, copy, preview, and Large Mode behavior remain compatibility gates. There is no separate verification task or repair budget inherited from MY-1484.

## Project Structure

### Documentation

```text
specs/026-reliable-editable-subset-rows/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── contracts/
│   └── row-and-deletion-contract.md
├── quickstart.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Implementation and Test Paths

```text
VitalStride/Sources/
├── VitalStrideApp.swift                         # DEBUG production host only
└── ActiveWorkout/
    ├── SetRow.swift
    ├── SubSetRow.swift
    ├── ActiveExerciseSection.swift
    └── SetDeletionRequest.swift                 # proposed app-internal deep module

VitalStrideTests/Sources/
├── SubSetDeletionUndoTests.swift
├── SubSetReadOnlyTests.swift                    # remove obsolete suite/file
├── SharedEditableSetRowTests.swift              # replacement compatibility suite
├── ActiveExerciseRowContextsTests.swift
└── ActiveWorkoutHitTargetTests.swift

VitalStrideUITests/Sources/
└── SubSetProductionRouteUITests.swift
```

**Structure Decision**: AppUI owns production code, unit/integration tests, and UI tests. The app-internal request module is the deep seam: the section knows one request operation, while policy, mutation, success effects, and result construction stay hidden behind it.

## Implementation Allowlist

Editable implementation paths:

- `VitalStride/Sources/ActiveWorkout/SetRow.swift`
- `VitalStride/Sources/ActiveWorkout/SubSetRow.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStride/Sources/ActiveWorkout/SetDeletionRequest.swift` (new)
- `VitalStride/Sources/VitalStrideApp.swift` (DEBUG test host only)
- `VitalStrideTests/Sources/SubSetDeletionUndoTests.swift`
- `VitalStrideTests/Sources/SubSetReadOnlyTests.swift` (delete after moving retained compatibility assertions)
- `VitalStrideTests/Sources/SharedEditableSetRowTests.swift` (new)
- `VitalStrideTests/Sources/ActiveExerciseRowContextsTests.swift`
- `VitalStrideTests/Sources/ActiveWorkoutHitTargetTests.swift`
- `VitalStrideUITests/Sources/SubSetProductionRouteUITests.swift` (new)

The reviewed `specs/026-reliable-editable-subset-rows/**` folder is inherited immutable planning evidence in the implementation PR, not an editable implementation path.

## Files Not to Touch

- `Packages/**`, especially `SetType`, `WorkoutSetManager`, and `WorkoutSetTree`
- `VitalStride/Sources/ActiveWorkout/SetDeletionPolicy.swift`
- `VitalStride/Sources/ActiveWorkout/SetDeletionFocusTarget.swift`
- `VitalStride/Sources/ActiveWorkout/SetDeletionUndoController.swift`
- `VitalStride/Sources/ActiveWorkoutView.swift`
- `VitalStride/Sources/WorkoutNumericKeyboard.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`
- `VitalStride/Resources/Localizable.xcstrings`
- `project.yml` and `VitalStride.xcodeproj/**`
- macOS/watchOS/widget targets and every unrelated app/test path
- stopped MY-1484 worktree/candidate and Draft PR #422

## Public Interface and Dependencies

No public interface. Proposed row identity, request result, request module, counting probe, and DEBUG host are app-internal. Production dependencies remain one-way from AppUI to existing `VitalModels`, `VitalUI`, and `DesignKit`; no new package or remote dependency is introduced.

## Verification Strategy

From repository root:

1. Capture focused RED failures before production edits for the request seam, shared editable composition, real menu/full-swipe activation, and adjacent-frame acceptance.
2. Regenerate the Xcode project ephemerally so the proposed production/test files are present in its explicit build phases, then run focused unit/UI acceptance on iPhone 17 Simulator. The generated project output is verification state only and is never staged or committed:

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
```

3. Run the canonical AppUI gate: `bash scripts/ci/run-app-target-tests.sh`.
4. Run catalog parity: `python3 scripts/i18n_check_lproj_parity.py`.
5. Before freezing the candidate, discard only the ephemeral `VitalStride.xcodeproj/**` regeneration output, verify `project.yml` and `VitalStride.xcodeproj/**` are unchanged, export `DELIVERY_BASE_SHA` from the registered issue metadata/Team Lead handoff, fail if it is empty, inspect `git diff --name-only "${DELIVERY_BASE_SHA}"` against the editable allowlist (including the uncommitted candidate), and verify `specs/026-reliable-editable-subset-rows/**` is byte-identical to that revision.
6. Capture the production-hosted standard/pyramid/drop-set stack on iPhone 17 Simulator in normal-light, normal-dark, Large-light, and Large-dark; record menu delete, committed full swipe, undo, the production-reachable cascade refusal, confirmation, child subtype/RPE changes, copy, catalog identity, no-child-history-query evidence, and action-menu-trigger frames.

## Complexity Tracking

No constitution violation or cross-layer exception is required. One DEBUG observation host is justified because XCUITest must activate and measure production configuration deterministically; it is explicitly prohibited from becoming an alternate action or deletion path.
