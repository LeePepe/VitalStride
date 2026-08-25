---
description: "Layer-scoped implementation tasks for MY-1476 active-workout safe-area stability"
---

# Tasks: Active Workout Safe-Area Stability

**Input**: `specs/023-active-workout-safe-area/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `contracts/active-workout-layout.md`, `quickstart.md`

**Constitution refs**: §II, §III, §IV, §Cross-Cutting Quality Bars A/G/H/I/K

## Phase 1: User Story 1 — Stable set editing across keyboard transitions (P1)

**Goal**: Keyboard show/hide is stable for snackbar none/rest/undo; focused content, snackbar, FAB, and final-row scroll clearance remain valid.

**Independent Test**: Execute the six-state automated matrix, both transition directions, the full AppUI gate, and the iPhone 16 light/dark interaction runbook.

- [ ] T001 [US1] Test-drive and implement the stable production layout policy in `VitalStride/Sources/ActiveWorkoutView.swift`, `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`, `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift`, and `VitalStrideTests/Sources/ActiveWorkoutSnackbarSafeAreaTests.swift`
- [ ] T002 [US1] Verify the completed `ActiveWorkoutView` layout with the focused/full AppUI gates and attach continuous light/dark iPhone 16 Simulator recordings spanning the complete keyboard show/hide animations plus a settled no-snackbar screenshot to MY-1476; make no repository source changes

## Task Metadata

### T001 — AppUI implementation and regression coverage

| Field | Contract |
|---|---|
| Owning layer | AppUI — `VitalStride/CONTEXT.md` |
| Vertical slice | US1 |
| Files in scope | `VitalStride/Sources/ActiveWorkoutView.swift`; `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`; `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift`; `VitalStrideTests/Sources/ActiveWorkoutSnackbarSafeAreaTests.swift` |
| Files/layers out of scope | `Packages/**`; `project.yml`; `VitalStride.xcodeproj/**`; `SelectAllTextField`; snackbar copy/timer/arbitration/persistence/telemetry; unrelated ActiveWorkout modules; `VitalStrideUITests/Sources/SnackbarAccessibilityUITests.swift` (must continue to pass unchanged) |
| Interface impact | Internal-only: deepen existing `ActiveWorkoutSnackbarLayout` and its `ActiveWorkoutView` call site; preserve `SnackbarFocusRouter`; no public interface |
| Test-first acceptance | RED covers keyboard hidden/visible × none/rest/undo through the production policy and fails on complete bottom-subtree removal/duplicate root geometry; GREEN satisfies `contracts/active-workout-layout.md`; REFACTOR removes stale production-unused edge/pass-through assumptions |
| Functional acceptance | Stable root bottom composition; exactly one active snackbar; hidden-keyboard FAB above active snackbar; focused row clears keyboard; final row clears active lower chrome; compact/Large Mode share policy; accessibility/focus remain valid |
| Verification | From repo root: `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/ActiveWorkoutSnackbarLayoutTests -only-testing:VitalStrideTests/ActiveWorkoutSnackbarSafeAreaTests` |
| Blocking tasks | None |

### T002 — AppUI assembled verification and visual evidence

| Field | Contract |
|---|---|
| Owning layer | AppUI verification — `VitalStride/CONTEXT.md` |
| Vertical slice | US1 |
| Files in scope | None; verification-only task against the T001 revision |
| Files/layers out of scope | All repository edits. A discovered failure returns to T001 scope instead of expanding this task. |
| Interface impact | None |
| Acceptance | Full AppUI suite passes; two continuous iPhone 16 recordings, one light and one dark, each start before field focus and span the complete keyboard show and hide animations with an active snackbar and final-row visibility; one settled light screenshot proves no-snackbar FAB spacing and final-row clearance; all three files are attached to MY-1476 |
| Verification | From repo root: `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation`; then `xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation` and execute `quickstart.md` |
| Blocking tasks | T001 |

## Dependencies and Execution Order

```text
US1: T001 (AppUI test-first implementation) → T002 (AppUI gate + visual evidence)
```

- T001 and T002 are sequential; no `[P]` marker is valid.
- T001 owns every repository edit. T002 is independently schedulable only after the exact T001 revision is available.
- The graph is acyclic and remains within the single AppUI owner layer.

## Acceptance Traceability

| Spec acceptance | Slice | Task evidence |
|---|---|---|
| Rest snackbar keyboard show/hide stability | US1 | T001 matrix/transition tests; T002 visual capture |
| Undo snackbar reachability and focus migration | US1 | T001 matrix/focus assertions; T002 visual capture |
| No-snackbar spacing and FAB return | US1 | T001 none-state assertions; T002 settled no-snackbar screenshot |
| Hidden-keyboard FAB/snackbar non-overlap and final-row clearance | US1 | T001 host geometry; T002 final-row runbook |
| Visible-keyboard focused-row/snackbar/keyboard clearance | US1 | T001 production-policy geometry; T002 interaction runbook |
| iPhone 16 light/dark evidence across both transitions | US1 | T002 attached continuous light and dark recordings spanning complete show and hide animations |

## Requirement Traceability

| Requirement | Slice | Owning task |
|---|---|---|
| FR-001 stable root safe-area composition | US1 | T001 |
| FR-002 deterministic six-state production policy | US1 | T001 |
| FR-003 single animation owner | US1 | T001 |
| FR-004 hidden-keyboard FAB/snackbar geometry | US1 | T001, verified by T002 |
| FR-005 visible-keyboard row/snackbar clearance without frame probing | US1 | T001, verified by T002 |
| FR-006 single active accessible snackbar and focus preservation | US1 | T001 |
| FR-007 final-row scroll clearance | US1 | T001, verified by T002 |
| FR-008 tests-first matrix and transition coverage | US1 | T001 |
| FR-009 AppUI gate plus iPhone 16 light/dark evidence | US1 | T002 |

## Implementation Strategy

Deliver US1 as one AppUI implementation revision, then run the separate verification-only task. Do not split overlapping production and test files across sibling implementation tickets.
