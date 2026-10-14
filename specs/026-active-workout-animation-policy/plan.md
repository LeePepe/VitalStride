# Implementation Plan: Active Workout Concurrency-Safe Animation Policy

**Branch**: `026-active-workout-animation-policy` | **Date**: 2026-10-14 | **Spec**: `specs/026-active-workout-animation-policy/spec.md`

**Input**: MY-1706, current `main@e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`, and the Owner-approved successor direction recorded on MY-1486.

## Summary

Deepen the existing internal `ActiveWorkoutSnackbarLayout` module so one small, `@MainActor`-isolated interface owns both the six-state layout decision and SwiftUI animation/transition ownership. `ActiveWorkoutView` consumes that interface once while keeping the root safe-area composition structurally stable. `ActiveWorkoutSnackbarLayoutTests` exercises the same production policy and mutation-tests exactly one root owner, no child animation, and no child transition.

This is a fresh implementation from current `main`; the stopped MY-1486 candidate is evidence for the accepted regression intent only and is not an implementation input.

## Technical Context

**Language/Version**: Swift 6.0 with strict concurrency

**Primary Dependencies**: SwiftUI and existing AppUI DesignKit consumption

**Storage**: N/A; no persistence changes

**Testing**: Swift Testing plus the existing UIKit-hosted SwiftUI geometry suites in `VitalStrideTests`

**Target Platform**: iOS 18.0+; iPhone 17 Simulator is the authoritative AppUI test destination and iPhone 16 Simulator remains the downstream visual-evidence destination

**Project Type**: XcodeGen-managed Apple app; AppUI-only change

**Performance Goals**: One intentional geometry-animation owner; no polling, timer, keyboard-frame observer, or duplicate transition

**Constraints**: Three writable paths; internal-only interface; `@MainActor` SwiftUI isolation; no unchecked/unsafe concurrency escape; no reuse of stopped candidate

**Scale/Scope**: One screen, two production files, one writable test file, one downstream verification-only issue

## Constitution Check

### Pre-design gate

| Constraint | Result | Evidence |
|---|---|---|
| §II strict concurrency / Quality Bar C | PASS | The selected design isolates SwiftUI-bearing policy to `@MainActor`; no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` is allowed. |
| §III AppUI ownership | PASS | All three writable paths resolve to AppUI through `VitalStride/CONTEXT.md`; no package work is needed. |
| §IV XcodeGen source of truth | PASS | No target or build-setting change; `project.yml` and generated xcodeproj are excluded. |
| Quality Bar A scope discipline | PASS | Exactly three writable files are declared; every other production/test path is excluded. |
| Quality Bars G/H/I/K | PASS | Existing localization/accessibility contracts are preserved; focused automation and existing downstream simulator evidence remain explicit. |
| PR-2 duplicate prevention | PASS | MY-1476 children were read before creation; MY-1706 is the only alive successor and was created parked in stage 1. |

### Post-design gate

PASS. The design deepens the existing AppUI module at its existing seam, keeps production/tests on one interface, adds no adapter or dependency direction, and requires no ADR, domain-context, public-interface, or data-model change.

## Current-State Evidence

Evidence is bound to `main@e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`:

- `VitalStride/Sources/ActiveWorkoutView.swift:97-163` conditionally replaces header composition, conditionally inserts/removes the entire bottom inset child, adds a child transition, and separately animates keyboard/snackbar state at the root.
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift` already owns MainActor-isolated top/bottom composition helpers, stable envelopes, accessibility representation, and focus-compatible placement, making it the existing seam to deepen.
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift` verifies isolated FAB height and edge selection but does not drive the six-state production policy or reject restored duplicate animation/transition ownership.
- The final MY-1486 exact-revision review established that a production-consumed root/child ownership policy plus three mutation checks resolves the prior FR-003/FR-008 feature-intent defect; publication failed only because that candidate added unapproved `@unchecked Sendable`.

## Design

### Chosen module shape

`ActiveWorkoutSnackbarLayout` remains the internal AppUI module. Its interface accepts state already known by `ActiveWorkoutView`, returns the presentation decision production needs, and exposes only the animation/transition ownership facts required by the caller and tests.

The seam stays inside the existing SwiftUI module and is `@MainActor` isolated. This gives callers leverage and maintainers locality: the caller does not independently decide root mounting, top/bottom placement, root animation, child animation, and child transition, while tests cross the same interface as production.

Concrete compile-level symbol names and Swift signatures are intentionally implementation-owned.

### Animation ownership and actor isolation

- The production policy represents the root animation owner, the absence/presence of a child animation owner, and the absence/presence of a child transition.
- The production configuration has one root owner, no child animation owner, and no child transition.
- `ActiveWorkoutView` derives the relevant modifiers only from this policy; there is no second hard-coded animation/transition decision at the call site.
- SwiftUI-bearing values are created and consumed on `@MainActor`. The policy is not required to cross actors and must not claim unchecked sendability.
- Snackbar-local content progress animation that does not drive the root safe-area geometry remains outside this ownership invariant.

### Stable composition

The root bottom safe-area composition remains structurally mounted for both keyboard states. Policy controls visible placement and interaction without deleting the complete subtree. The same six-state policy covers none/rest/undo and compact/Large Mode.

### Mutation-sensitive regression surface

Tests instantiate or derive from the same production policy and prove the invariant rejects each independent mutation:

1. add a child geometry-animation driver;
2. add a child insertion/removal transition;
3. omit the root animation driver.

The test must not infer ownership from trajectory monotonicity alone or assert a production-unused constant.

### Accessibility and compatibility

Exactly one snackbar presentation is interactive and represented to accessibility. Existing `BottomSnackbarSlot`, `SnackbarFocusRouter`, envelopes, Dynamic Type, localized text, and action targets remain compatible. Timer, undo, parsing, persistence, and telemetry do not enter the module interface.

### Alternatives rejected

1. **Checked-Sendable descriptors plus main-actor conversion**: allowed by the Owner direction but rejected for this successor because no cross-actor transport exists. It would add a descriptor/conversion seam with one adapter and less locality than extending the existing MainActor SwiftUI seam.
2. **Unchecked sendability around SwiftUI values**: prohibited by Constitution §II / Quality Bar C and the explicit successor scope.
3. **Keep conditional root subtrees and tune durations**: preserves coupled system avoidance, bottom removal, header replacement, and duplicate ownership.
4. **Read keyboard frames and offset overlays**: adds brittle coupling and violates the accepted no-frame-probing contract.
5. **Copy or cherry-pick MY-1486 candidate**: explicitly prohibited; implementation begins from the reviewed planning revision based on current `main`.

## Project Structure

### Documentation for this feature

```text
specs/026-active-workout-animation-policy/
├── spec.md
├── plan.md
├── research.md
├── contracts/
│   └── active-workout-animation-policy.md
├── quickstart.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

`data-model.md` is not applicable because no entity, schema, or persisted state changes.

### Source code

```text
VitalStride/Sources/
├── ActiveWorkoutView.swift
└── ActiveWorkout/
    └── ActiveWorkoutSnackbarLayout.swift

VitalStrideTests/Sources/
└── ActiveWorkoutSnackbarLayoutTests.swift
```

**Structure Decision**: Keep all implementation and writable regression coverage in the existing AppUI module. Existing broader safe-area and accessibility tests are verification inputs but remain read-only.

## Delivery Strategy

### Vertical slice and task graph

US1 is realized by one replacement AppUI implementation task, MY-1706 / T001. Existing MY-1487 / T002 remains the downstream verification-only task and depends on the completed successor rather than MY-1486.

```text
MY-1706 / T001 (AppUI test-first implementation) → MY-1487 / T002 (full AppUI + simulator evidence)
```

### Test-first sequence inside T001

1. **RED**: replace production-unused/non-mutation-sensitive confidence with six-state production-policy coverage and the three independent owner mutations.
2. **GREEN**: deepen the existing MainActor seam, keep the root bottom composition mounted, and derive root/child modifiers from one policy.
3. **REFACTOR**: remove redundant caller decisions while preserving focus, accessibility, timer, undo, and static safe-area contracts.

### Planning and implementation base

- Planning branch base: exact current `main@e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- Implementation base: the exact pushed planning revision after AI Reviewer PASS and Team Lead acceptance.
- The stopped MY-1486 candidate, its branch, workspace, and Draft PR #420 are not source material or delivery state for MY-1706.

## Verification Commands

Run from the repository root.

Focused successor verification:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/ActiveWorkoutSnackbarLayoutTests -only-testing:VitalStrideTests/ActiveWorkoutSnackbarSafeAreaTests
```

Downstream MY-1487 authoritative AppUI gate:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation
```

MY-1487 then follows `quickstart.md` to clean-build the exact delivered successor revision, assert the bundle identifier, install/launch it on one dedicated iPhone 16 Simulator UDID, and capture the complete light/rest and dark/undo keyboard transitions plus settled no-snackbar evidence.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| MainActor isolation is weakened to make tests compile | FR-004 and Quality Bar C prohibit escapes; tests are MainActor-aware and review searches all three writable paths. |
| Policy exists but production hard-codes a second modifier | Contract requires caller modifiers to derive from the production-consumed policy; mutation tests target all three ownership fields. |
| Stable but inactive content remains interactive/accessibility-visible | Preserve existing accessibility representation/focus seams and six-state assertions. |
| Fresh work silently reuses the stopped candidate | Start from the reviewed planning revision based on `e8cfc19`; no cherry-pick/copy and no MY-1486 workspace or PR mutation. |
| MY-1487 verifies the wrong predecessor | Update its textual dependency only after exact planning PASS and keep it parked until MY-1706 normal delivery completes. |

## Complexity Tracking

No constitution violation or complexity waiver is required.
