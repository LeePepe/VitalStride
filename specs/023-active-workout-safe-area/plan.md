# Implementation Plan: Active Workout Safe-Area Stability

**Branch**: `023-active-workout-safe-area` | **Date**: 2026-08-25 | **Spec**: `specs/023-active-workout-safe-area/spec.md`

**Input**: MY-1476 and the current AppUI layout at repository revision `332f8e9a0a2e299303ddde9e79b90336499b83f5`.

## Summary

Deepen the existing internal `ActiveWorkoutSnackbarLayout` module so one small interface owns keyboard/snackbar placement and bottom-space reservation. `ActiveWorkoutView` will attach one stable root safe-area composition and supply current state and content once. Regression coverage will exercise the same production policy for keyboard visible/hidden crossed with snackbar none/rest/undo, then verify the full AppUI gate and iPhone 16 light/dark transitions.

## Technical Context

**Language/Version**: Swift 6.0 with strict concurrency

**Primary Dependencies**: SwiftUI, UIKit keyboard notifications on iOS, DesignKit tokens already consumed by AppUI

**Storage**: N/A; no persistence changes

**Testing**: Swift Testing and UIKit-hosted SwiftUI geometry checks inside the `VitalStrideTests` app-test target

**Target Platform**: iOS 18.0+; iPhone 17 Simulator is the authoritative AppUI test destination, while iPhone 16 Simulator is the required visual-evidence destination for MY-1476

**Project Type**: XcodeGen-managed multi-target Apple app; this change is AppUI-only

**Performance Goals**: Keyboard transition settles without redundant root geometry animation; no polling, timers, or keyboard-frame observers are added

**Constraints**: Internal-only interface, stable root subtree, no private keyboard geometry, no package or project configuration changes

**Scale/Scope**: One active-workout screen, two production files, and two focused test files

## Constitution Check

### Pre-design gate

| Constraint | Result | Evidence |
|---|---|---|
| §II strict concurrency | PASS | Preserve existing MainActor-isolated SwiftUI helpers; no unsafe concurrency escape is planned. |
| §III layer ownership | PASS | All production and test paths are owned by AppUI per `VitalStride/CONTEXT.md`; no `Packages/**` work is needed. |
| §IV XcodeGen source of truth | PASS | No target or build-setting change; `project.yml` and generated xcodeproj are excluded. |
| Quality Bar A scope discipline | PASS | Four narrow files are listed; timer, undo, parsing, persistence, and packages are excluded. |
| Quality Bars G/H/I/K | PASS | Existing localization and accessibility behavior are preserved; matrix tests and iPhone 16 light/dark evidence are explicit. |

### Post-design gate

PASS. The selected design reuses and deepens the existing AppUI layout seam, introduces no new dependency direction, and leaves public interfaces, data, and domain language unchanged. No ADR or `CONTEXT.md` edit is warranted.

## Current-State Evidence

- `VitalStride/Sources/ActiveWorkoutView.swift:100-133` conditionally replaces the standalone header with a top snackbar composition when the keyboard appears.
- `VitalStride/Sources/ActiveWorkoutView.swift:142-160` conditionally inserts or removes the entire FAB/snackbar child of the root bottom safe-area inset.
- `VitalStride/Sources/ActiveWorkoutView.swift:159-163` combines a child transition with root animations for keyboard and snackbar state.
- `VitalStride/Sources/ActiveWorkoutView.swift:389-398` drives keyboard state from UIKit show/hide notifications.
- `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift:22-148` already owns stable snackbar envelopes and top/bottom composition helpers, making it the existing seam to deepen.
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift:29-87` checks a pass-through FAB wrapper and a production-unused edge resolver; it does not exercise root transitions.
- `VitalStrideTests/Sources/ActiveWorkoutSnackbarSafeAreaTests.swift:27-266` covers static non-overlap and containment but not one keyboard-aware production composition across the full state matrix.

## Design

### Chosen module shape

`ActiveWorkoutSnackbarLayout` remains an internal AppUI module. Its interface will accept the state already known by `ActiveWorkoutView` and own the placement/reservation decision for the full keyboard/snackbar matrix. The root view calls this seam once and keeps the bottom safe-area composition structurally present across keyboard transitions.

This shape is deeper than the current split: callers no longer need to know when to replace the header, when to remove the entire inset child, and which animations accompany both operations. Tests cross the same seam as production and verify behavior rather than production-unused edge selection.

The behavioral contract is in `contracts/active-workout-layout.md`. Concrete new symbol names and compile-level Swift signatures are intentionally left to the Fullstack Engineer.

### Animation ownership

Keyboard state has one intentional presentation-change owner; the same layout movement will not be driven by both a root implicit animation and a child insertion/removal transition. Snackbar content transitions remain local and do not alter the root scroll-avoidance contract.

### Accessibility and interaction

Exactly one snackbar presentation is interactive and represented to accessibility. Existing `SnackbarFocusRouter`, stable undo/rest envelopes, Dynamic Type behavior, and action targets remain part of the contract. Inactive duplicate layout regions must not receive hit testing or VoiceOver focus.

### Alternatives rejected

1. Keep the conditional root subtrees and tune animation durations: rejected because it preserves the coupled system-safe-area, bottom-removal, and header-insertion feedback loop.
2. Read keyboard frames and manually offset overlays: rejected because MY-1476 and the constitution forbid private or brittle keyboard-geometry coupling.
3. Move the layout into a package: rejected because the behavior is app-specific SwiftUI composition and the existing AppUI seam is sufficient.
4. Split tests and implementation into separate tickets: rejected because both touch the same AppUI files and a red-only test ticket would not be independently deliverable.

## Project Structure

### Documentation for this feature

```text
specs/023-active-workout-safe-area/
├── spec.md
├── plan.md
├── research.md
├── contracts/
│   └── active-workout-layout.md
├── quickstart.md
└── tasks.md
```

`data-model.md` is not applicable because the feature changes no entity, persisted state, or schema.

### Source code

```text
VitalStride/Sources/
├── ActiveWorkoutView.swift
└── ActiveWorkout/
    └── ActiveWorkoutSnackbarLayout.swift

VitalStrideTests/Sources/
├── ActiveWorkoutSnackbarLayoutTests.swift
└── ActiveWorkoutSnackbarSafeAreaTests.swift
```

**Structure Decision**: Keep production layout policy and app-test verification inside the single AppUI layer. Do not introduce a new module seam outside the existing internal helper.

## Delivery Strategy

### Vertical slice

US1 delivers the complete user outcome: stable numeric editing across all snackbar states. It is realized by one AppUI implementation task followed by one AppUI verification-only task.

### Test-first sequence inside T001

1. RED: replace production-unused/vacuous assertions with a table-driven six-state policy test and host-geometry regression checks that fail on the current conditional root composition.
2. GREEN: deepen the existing internal layout seam and make `ActiveWorkoutView` attach one stable safe-area composition.
3. REFACTOR: remove stale pass-through/edge-only test assumptions and redundant root animation ownership while preserving focus, accessibility, timer, and undo behavior.

### Verification sequence

1. Focused AppUI suites on iPhone 17 Simulator.
2. Full AppUI layer command on iPhone 17 Simulator.
3. Continuous iPhone 16 Simulator light/dark recordings spanning the complete keyboard show and hide animations with active snackbar and final-row visibility.

## Verification Commands

Run from the repository root.

Focused regression suites:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/ActiveWorkoutSnackbarLayoutTests -only-testing:VitalStrideTests/ActiveWorkoutSnackbarSafeAreaTests
```

Authoritative AppUI layer gate:

```bash
xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation
```

Generic AppUI build before visual evidence:

```bash
xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation
```

The Fullstack Engineer then boots an iPhone 16 Simulator, performs the `quickstart.md` interaction sequence, and attaches two continuous recordings to MY-1476: one light and one dark. Each recording starts before focusing the field, captures the entire keyboard show animation and settled visible state, then captures the entire hide animation and settled hidden state. A separate settled light screenshot proves no-snackbar FAB spacing and final-row clearance. Runtime-local evidence paths are not deliverables.

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| A stable but inactive region remains interactive or accessible | Matrix tests assert single active placement; preserve accessibility replacement and focus routing. |
| Constant reservation wastes space or double-counts the keyboard | Contract distinguishes structural stability from visible/reserved policy and verifies focused-row clearance on both keyboard states. |
| Large Mode diverges from compact mode | Both header variants must pass through the same root layout contract. |
| Stale tests keep passing without production coverage | Replace production-unused edge/pass-through assertions with tests that exercise the production layout policy. |
| Simulator destination confusion hides a gate | Use the generic simulator destination for build, iPhone 17 for automated AppUI tests, and iPhone 16 only for issue-mandated visual recording. |

## Complexity Tracking

No constitution violation or additional complexity waiver is required.
