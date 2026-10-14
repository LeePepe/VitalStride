---
description: "Layer-scoped successor tasks for MY-1476 ActiveWorkout animation ownership"
---

# Tasks: Active Workout Concurrency-Safe Animation Policy

**Input**: `specs/026-active-workout-animation-policy/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `contracts/active-workout-animation-policy.md`, `quickstart.md`

**Constitution refs**: §II, §III, §IV, §Cross-Cutting Quality Bars A/C/G/H/I/K

**Tracker mapping**: T001 is the single new successor MY-1706. T002 is the already-existing parked verification issue MY-1487; this planning revision creates no second successor.

## Phase 1: User Story 1 — Stable set editing with one animation owner (P1)

**Goal**: Keyboard show/hide is stable for snackbar none/rest/undo, one MainActor-isolated production policy owns root/child animation facts, and the regression guard rejects every duplicate-owner mutation.

**Independent Test**: Execute the six-state production-policy matrix, both transition directions, the three independent ownership mutations, and the unchanged safe-area geometry suite.

- [ ] T001 [US1] Freshly test-drive and implement the MainActor-isolated production layout/animation policy for MY-1706 in `VitalStride/Sources/ActiveWorkoutView.swift`, `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`, and `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift`
- [ ] T002 [US1] On existing MY-1487, verify the delivered MY-1706 revision with the full AppUI gate and one dedicated iPhone 16 Simulator, then attach continuous light/rest and dark/undo keyboard-transition recordings plus a settled no-snackbar screenshot to MY-1476; make no repository source changes

## Task Metadata

### T001 — MY-1706 AppUI successor implementation and regression coverage

| Field | Contract |
|---|---|
| Owning layer | AppUI — `VitalStride/CONTEXT.md` |
| Vertical slice | US1 |
| Files in scope | `VitalStride/Sources/ActiveWorkoutView.swift`; `VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift`; `VitalStrideTests/Sources/ActiveWorkoutSnackbarLayoutTests.swift` |
| Files/layers out of scope | Every other path, including `ActiveWorkoutSnackbarSafeAreaTests.swift`, `SnackbarAccessibilityUITests.swift`, `Packages/**`, `project.yml`, xcodeproj, `SelectAllTextField`, timer/undo/persistence/telemetry, MY-1486 workspace/candidate/PR |
| Interface impact | Internal-only: deepen existing `ActiveWorkoutSnackbarLayout` and its sole `ActiveWorkoutView` call site; preserve `SnackbarFocusRouter`; no public interface |
| Actor contract | SwiftUI-bearing policy creation/consumption is `@MainActor`; no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` |
| Test-first acceptance | RED covers six production states and independently fails for child-animation, child-transition, and missing-root-owner mutations; GREEN satisfies the behavioral contract; REFACTOR removes redundant caller ownership |
| Functional acceptance | US1/AC1–US1/AC6; FR-001–FR-009 |
| Verification | From repo root: `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/ActiveWorkoutSnackbarLayoutTests -only-testing:VitalStrideTests/ActiveWorkoutSnackbarSafeAreaTests` |
| Blocking tasks | None after the exact planning revision receives AI Reviewer PASS and Team Lead accepts readiness |
| Delivery base | Exact reviewed planning revision based on `main@e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`; do not reuse MY-1486 candidate content |

### T002 — Existing MY-1487 assembled verification and visual evidence

| Field | Contract |
|---|---|
| Owning layer | AppUI verification — `VitalStride/CONTEXT.md` |
| Vertical slice | US1 |
| Files in scope | None; verification-only against the exact delivered MY-1706 implementation revision |
| Files/layers out of scope | All repository edits. A discovered failure returns to MY-1706 scope through Team Lead instead of expanding MY-1487. |
| Interface impact | None |
| Acceptance | Full AppUI suite passes; exact revision-keyed Debug build/bundle ID is asserted; one explicit iPhone 16 UDID is used for both complete show/hide recordings and no-snackbar screenshot; evidence plus revision/UDID is attached to MY-1476 |
| Verification | From repo root: full AppUI command from `plan.md`, then every build/assert/install/launch/capture step in `quickstart.md` |
| Blocking tasks | T001 / MY-1706 normal delivery completed with exact accepted implementation revision |
| Invalid inputs | MY-1486 candidate, branch, workspace, and Draft PR #420 |

## Dependencies and Execution Order

```text
US1: T001 / MY-1706 (fresh AppUI test-first implementation)
  → T002 / existing MY-1487 (full AppUI + simulator evidence)
```

- T001 and T002 are sequential; no `[P]` marker is valid.
- T001 owns every repository edit and exactly three paths.
- T002 remains backlog/stage 2 and is schedulable only after MY-1706 normal delivery completes.
- The graph is acyclic and remains within the AppUI owner layer.
- MY-1486 and Draft PR #420 are terminal predecessor history, not dependency inputs.

## Acceptance Traceability

| Acceptance | Slice | Task evidence |
|---|---|---|
| US1/AC1 stable root + single active snackbar | US1 | T001 production-policy matrix; T002 visual capture |
| US1/AC2 one root owner, no child animation/transition | US1 | T001 production-consumed policy assertions |
| US1/AC3 three independent mutations fail | US1 | T001 mutation-sensitive regression |
| US1/AC4 hidden-keyboard bottom geometry/final row | US1 | T001 focused geometry suite; T002 no-snackbar screenshot |
| US1/AC5 visible-keyboard clearance | US1 | T001 policy/geometry; T002 interaction recordings |
| US1/AC6 modes/accessibility compatibility | US1 | T001 unchanged behavior/suites; T002 visual gate |

## Requirement Traceability

| Requirement | Slice | Owning task |
|---|---|---|
| FR-001 stable root composition | US1 | T001 |
| FR-002 deterministic six-state policy | US1 | T001 |
| FR-003 explicit root/child ownership facts | US1 | T001 |
| FR-004 MainActor isolation/no escape | US1 | T001 |
| FR-005 three mutation failures | US1 | T001 |
| FR-006 FAB/snackbar/focused-row clearance | US1 | T001; verified by T002 |
| FR-007 single active accessible snackbar/focus | US1 | T001 |
| FR-008 final-row and compact/Large Mode parity | US1 | T001; verified by T002 |
| FR-009 exact three-path diff/no weakened test | US1 | T001 |

## Implementation Strategy

Deliver US1 as one fresh AppUI implementation revision, then run the existing verification-only MY-1487. Do not split overlapping production and test paths across sibling implementation issues, do not add a concurrency descriptor layer, and do not import predecessor candidate content.
