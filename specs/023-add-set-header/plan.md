# Implementation Plan: Add Set Action in Exercise Header

**Branch**: `023-add-set-header` | **Date**: 2026-08-25 | **Spec**: `specs/023-add-set-header/spec.md`

**Input**: MY-1474 and the feature specification in this directory.

## Summary

Deliver one AppUI vertical slice: prove the current add-set control is incorrectly present in `Section` content, move the existing private action into the exercise header beside the title and existing menu, preserve the current add-set mutation, and collect executable plus simulator accessibility/visual evidence. No package, model, localization, or public-interface change is involved.

## Technical Context

**Language/Version**: Swift 6 strict concurrency

**Primary Dependencies**: SwiftUI, SwiftData, VitalModels, VitalUI, DesignKit (all existing)

**Storage**: Existing SwiftData workout graph; no schema or migration change

**Testing**: Swift Testing in the `VitalStrideTests` iOS bundle; source-structure regression plus in-memory SwiftData behavior coverage; MY-1474 iPhone 16 test plus the formal AppUI iPhone 17 gate

**Target Platform**: iOS 18+; regression and visual evidence on iPhone 16 Simulator; formal AppUI gate on iPhone 17 Simulator

**Project Type**: Mobile app, AppUI change-owner layer

**Performance Goals**: No new asynchronous work or data traversal; one UI activation performs one existing append operation

**Constraints**: Planning is contract-level only; no public API changes; add-set defaults/order remain frozen; minimum 44-point target; Dynamic Type and VoiceOver usable; no `Packages/**`, `project.yml`, or localization changes

**Scale/Scope**: One production view, one new AppUI test file, one user story, two serial layer tasks

## Constitution Check

### Pre-design gate

| Rule | Result | Evidence |
|---|---|---|
| Principle II — Swift 6 strict concurrency | PASS | No concurrency boundary or escape hatch is introduced. |
| Principle III — AppUI versus packages | PASS | The platform-specific SwiftUI placement and app tests are owned by AppUI per `VitalStride/CONTEXT.md`; packages remain untouched. |
| Principle VI / Quality Bar G — localization | PASS | Existing localized label and hint are reused; `Localizable.xcstrings` is not authorized. |
| Quality Bar A — scope discipline | PASS | Production and test paths are pinned; sibling views, packages, models, and generated project files are excluded. |
| Quality Bar H — accessibility | PASS by contract | Tasks require 44-point geometry, Dynamic Type evidence, and VoiceOver label/hint evidence. |
| Quality Bar I — test coverage | PASS by contract | Regression-first structure and mutation coverage are mandatory before the production edit. |
| Quality Bar K — simulator visual evidence | PASS by contract | iPhone 16 Simulator light/dark plus accessibility-size evidence is required; no physical-device gate is introduced. |

### Post-design gate

PASS. Research, scope, dependency edges, automated verification, and manual evidence remain within one AppUI layer and introduce no constitutional exception or ADR need.

## Design Decisions

### D1 — New feature package instead of rewriting spec 017

`specs/017-add-set-button-redesign` is a historical record whose frozen contract keeps the action as the last list row. MY-1474 intentionally changes that placement, so it receives `specs/023-add-set-header/`; the old package is not edited.

### D2 — Header ownership and content-row invariant

The existing private add-set action moves into the `Section` header’s control group. The content closure retains only the `ForEach`-driven main-set and sub-set rows. This is the structural invariant that prevents edit-mode movement and the extra list row.

### D3 — Preserve mutation through an internal test seam

The existing add-set mutation remains the policy source of truth. If direct behavior testing requires a seam, the implementation may expose the minimum internal-only helper in the same production file; its concrete name and parameter labels are implementation-owned. Tests must prove one append, last-main-set default copying, and continuous order. No public signature changes.

### D4 — Reuse existing copy and styling assets

The existing localized label/hint and private pressed-state style remain available. The header presentation becomes compact enough for the header while retaining a 44-point target. Row-only infinite-width, inset, background, and separator modifiers are removed from the moved control. The existing normal/large × light/dark previews remain, but their names/comments must describe the header placement rather than the historical row placement. No new string, token, component, or dependency is required.

### D5 — Evidence split

Automated tests own the content/header structural invariant and add-set mutation. Simulator evidence owns header crowding, light/dark appearance, accessibility-size layout, and VoiceOver announcement. The full app-target command remains the declared executable gate.

## Project Structure

### Documentation (this feature)

```text
specs/023-add-set-header/
├── checklists/
│   └── requirements.md
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── tasks.md
```

No `contracts/` artifact is needed because the slice is internal to AppUI and changes no public or cross-layer contract.

### Source Code (repository root)

```text
VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift
VitalStrideTests/Sources/ActiveExerciseSectionAddSetHeaderTests.swift
```

**Structure Decision**: Both paths belong to the `AppUI` layer. The production view remains the sole header/layout owner, and the new test file owns the regression and mutation proof.

## Delivery Strategy

The single vertical slice is delivered by two serial AppUI tasks:

1. Establish a regression test that fails because the add-set action is still a content row, then move the action and complete behavior/accessibility coverage while preserving the add mutation.
2. Run the full issue-specific and formal AppUI gates and capture the pinned simulator evidence.

The graph is `T001 → T002`; no task is parallel because T002 verifies the assembled T001 result.

## Verification Strategy

Run the targeted MY-1474 suite from the repository root for the RED and GREEN checkpoints:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation \
  -only-testing:VitalStrideTests/ActiveExerciseSectionAddSetHeaderTests
```

Regression-first proof is required before implementation: the targeted structure test must fail against the current `origin/main` layout because the add-set action is inside `Section` content, then pass after T001.

After implementation, run both complete gates from the repository root. The first is the exact command declared by MY-1474; the second is the formal AppUI layer gate from `VitalStride/CONTEXT.md` and the current constitution:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -skipPackagePluginValidation

xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -skipPackagePluginValidation
```

The final handoff must also show that only the authorized production/test files changed outside this planning package.

## Manual Evidence Contract

The implementation PR or handoff must contain:

- iPhone 16 Simulator before/after screenshot pairs at the default content size in both light and dark appearances. Each frame must show one full exercise header and at least two set rows; the after frame must keep the title, add action, and existing menu visible without overlap and remove the standalone add-set row.
- One iPhone 16 Simulator screenshot at an accessibility Dynamic Type size showing that the title adapts without shrinking or overlapping either 44-point control.
- A VoiceOver checklist result stating the add action is announced as a button with the existing localized add-set label and insertion hint, focus reaches the add action and exercise menu separately, and edit mode adds no move/reorder announcement to the add action.
- A hit-target result demonstrating both header controls are at least 44 by 44 points.

## Risk and Rollback

- **Primary risk**: header crowding with long names or accessibility text sizes. The explicit evidence matrix makes this visible before merge.
- **Behavior risk**: placement refactoring accidentally changes append policy. The in-memory mutation test freezes it.
- **Rollback**: revert the AppUI implementation commit; no data migration or public API rollback is required.

## Complexity Tracking

No constitutional violation or exception is required.
