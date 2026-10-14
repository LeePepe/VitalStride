---
description: "Layer-scoped delivery tasks for MY-1474"
---

# Tasks: Add Set Action in Exercise Header

**Input**: Design documents from `specs/023-add-set-header/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `quickstart.md`

**Constitution refs**: Principles II, III, and VI; Cross-Cutting Quality Bars A, G, H, I, and K; ADR-0014.

## Authorized Implementation Surface

- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift`

No localization resource, package, model, project configuration, generated project file, sibling ActiveWorkout view, or historical spec is authorized.

## Phase 1: User Story 1 — Add a set without creating an editable row (P1) 🎯 MVP

**Goal**: Keep the add-set action in the exercise header, remove it from editable list content, and preserve the current append behavior.

**Independent Test**: On an active workout with one exercise and at least two sets, edit mode exposes only real set rows; one activation of the header action appends exactly one correctly defaulted and ordered main set.

- [ ] T001 [US1] Write the regression first, then move the add-set action into the header and preserve its append behavior in `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift` and `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`

### T001 Metadata

| Field | Contract |
|---|---|
| Owning layer | `AppUI`; context: `VitalStride/CONTEXT.md` |
| Slice | US1 — add a set without creating an editable row |
| Files in scope | `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift`; `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` |
| Files and behavior out of scope | `ActiveWorkoutView` reorder behavior; every other file under `VitalStride/Sources/ActiveWorkout/`; `Packages/**`; set/sub-set models; `project.yml`; `VitalStride.xcodeproj/**`; localization resources; exercise-menu behavior; historical `specs/017-add-set-button-redesign/**` |
| Interface impact | Internal-only AppUI boundary. No public API change. Existing `ActiveExerciseSection` inputs and observable add-set policy remain unchanged. A minimum internal test seam may be introduced in the same production file only when needed for behavior coverage; its concrete signature is implementation-owned. |
| Depends on | None |
| Blocks | T002 |
| Regression-first acceptance | Add the structural regression before changing production source. Against the current layout it must compile and fail specifically because the add-set action is inside `Section` content. Retain the failing test identifier and assertion output in the handoff. Only then edit production source. |
| Structural acceptance | The `Section` content contains only the existing `ForEach`-driven main-set/sub-set rows. The add-set action occurs in the header control group beside the title and existing menu, cannot receive list-row edit/move behavior, and no longer carries the row-only infinite-width, `listRowInsets`, `listRowBackground`, or `listRowSeparator` presentation. |
| Behavior acceptance | One activation appends exactly one main set; weight, reps, set type, unilateral state, and right-side weight come from the last main set; order is the next continuous value; trailing sub-sets do not become the default source. |
| Accessibility acceptance | The action reuses the existing localized label and insertion hint, is exposed as a button, and has a minimum 44 by 44 point target. The existing exercise menu retains its own separate 44-point target and behavior. |
| Layout acceptance | Long exercise names, Dynamic Type, and Large Mode adapt without overlapping or shrinking either header control below the hit-target floor. Preserve the existing normal/large × light/dark preview matrix and update its names/comments so they describe header placement rather than the historical standalone row. |
| Exact layer verification | Run the targeted iPhone 16 suite below twice: RED after adding the regression but before the production edit (expected nonzero with only the new structural assertion failing), then GREEN after implementation (expected zero failures). |

### T001 Regression-First Verification

Run from the repository root at both RED and GREEN checkpoints:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ActiveExerciseSectionAddSetHeaderTests
```

The RED checkpoint is invalid if it fails to compile, fails for an unrelated pre-existing test, or does not identify the current content-row placement. The GREEN checkpoint is invalid unless the new structure and mutation assertions pass.

---

## Phase 2: Assembled AppUI Verification and Evidence

**Purpose**: Prove the completed slice at the declared app-target gate and collect the visual/accessibility evidence that automated structure and mutation checks cannot replace.

- [ ] T002 [US1] Verify `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` with `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift` and attach the iPhone 16 Simulator plus accessibility evidence to the implementation handoff

### T002 Metadata

| Field | Contract |
|---|---|
| Owning layer | `AppUI` integration/test surface; context: `VitalStride/CONTEXT.md` |
| Slice | US1 assembled verification |
| Files in scope | Read/verify `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` and `VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift`; no additional repository edit is authorized |
| Files and behavior out of scope | All repository paths not owned by T001; no opportunistic cleanup or evidence-only source change |
| Interface impact | None; verification only |
| Depends on | T001 |
| Blocks | Slice handoff to Team Lead / implementation review |
| Automatic acceptance | The exact MY-1474 iPhone 16 command and the formal AppUI iPhone 17 command both exit zero; the new regression suite passes; the implementation diff outside `specs/023-add-set-header/**` contains only the two authorized AppUI files. |
| Light/dark screenshot acceptance | Attach iPhone 16 Simulator before/after screenshot pairs at default content size in both light and dark appearances. Every frame must show one complete exercise header and at least two set rows; each after frame must keep the title, add action, and existing menu visible without overlap and remove the standalone add-set row. |
| Dynamic Type acceptance | Attach one iPhone 16 Simulator screenshot at an accessibility Dynamic Type size showing the title adapting without overlapping or shrinking the add action or menu below 44 points. |
| VoiceOver acceptance | Record a checklist result that the add action is announced as a button using the existing localized add-set label and insertion hint, focus reaches the add action and existing menu as distinct controls, and edit mode adds no move/reorder announcement to the add action. |
| Hit-target acceptance | Record measured or Accessibility Inspector evidence that both header controls are at least 44 by 44 points. |
| Exact layer verification | Run both complete app-target commands below from the repository root after all T001 changes. |

### T002 Complete App-Target Tests

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

---

## Dependencies and Scheduling

```text
US1: T001 (RED → GREEN AppUI implementation) → T002 (assembled gate + evidence)
```

- T001 and T002 are serial; neither is marked `[P]`.
- T001 owns every authorized repository edit.
- T002 is verification-only and may start only after T001 is green.
- There is no cross-layer dependency and no package task.

## Acceptance Traceability

| Spec acceptance | Vertical slice | Tasks |
|---|---|---|
| Add action is not an editable/movable content row | US1 | T001 structural regression; T002 screenshot and VoiceOver edit-mode confirmation |
| Add action is in the section header | US1 | T001 structural/layout acceptance; T002 light/dark evidence |
| One append preserves defaults and continuous order | US1 | T001 mutation coverage; T002 full app gate |
| 44-point target, Dynamic Type, VoiceOver label/hint | US1 | T001 accessibility contract; T002 inspector/checklist evidence |
| iPhone 16 Simulator before/after light/dark header is not crowded | US1 | T002 screenshot evidence |

## Definition of Ready

- [x] One independently demonstrable vertical slice maps every MY-1474 acceptance criterion.
- [x] Every executable task owns exactly one formal layer.
- [x] Authorized files and exclusions are exact.
- [x] Public-interface impact is explicitly none; internal test seam is bounded.
- [x] Dependency edges are acyclic and no false parallelism is declared.
- [x] Regression-first RED and GREEN evidence is pinned.
- [x] The issue-declared iPhone 16 command, formal AppUI iPhone 17 gate, and working directory are exact.
- [x] Before/after screenshot, Dynamic Type, VoiceOver edit-mode, and hit-target evidence are explicit.
