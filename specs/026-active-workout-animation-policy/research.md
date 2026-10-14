# Research: Active Workout Concurrency-Safe Animation Policy

## R1 — Authoritative base and predecessor disposition

**Finding**: The Owner terminated MY-1486, prohibited reuse/publication of local candidate `c563cc108c11e97646cb95bf6bc3cb288b0c781d`, and left Draft PR #420 unchanged. The successor must start from current `main@e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.

**Decision**: Bind planning to `e8cfc19`; treat predecessor review only as evidence for the accepted behavior/test intent. Do not copy, cherry-pick, publish, or mutate predecessor state.

## R2 — Root regression surface

**Finding**: Current `ActiveWorkoutView` conditionally removes the full bottom inset child, conditionally replaces the header composition, attaches a child transition, and applies root keyboard/snackbar animations.

**Decision**: The successor owns stable root composition and single geometry-animation ownership together. Duration tuning without structural ownership change is insufficient.

## R3 — Existing module seam

**Finding**: `ActiveWorkoutSnackbarLayout` already owns MainActor-isolated SwiftUI composition, accessibility representation, stable envelopes, and top/bottom presentation. `ActiveWorkoutView` is its production caller.

**Decision**: Deepen this module at the existing seam. Production and tests cross one interface; no new package or public interface.

## R4 — Concurrency-safe representation

**Finding**: SwiftUI `Animation` and transition values belong to the UI executor. No requirement sends the policy across actors. Constitution §II forbids unchecked/unsafe sendability without an ADR-recorded Apple boundary.

**Decision**: Isolate the SwiftUI-bearing policy and its construction/consumption to `@MainActor`. Do not add sendability conformance. A checked-Sendable descriptor conversion layer is unnecessary for this single-executor seam.

## R5 — Mutation-sensitive test intent

**Finding**: Trajectory monotonicity or a root-only constant can continue passing after a child animation/transition is restored. The prior accepted remediation explicitly modeled root and child ownership and tested three mutations.

**Decision**: The production-consumed policy must expose enough ownership state for tests to reject: added child animation, added child transition, and missing root owner. Keep these as three independent assertions.

## R6 — Scope and verification

**Finding**: The fresh implementation can be completed in `ActiveWorkoutView.swift`, `ActiveWorkoutSnackbarLayout.swift`, and `ActiveWorkoutSnackbarLayoutTests.swift`. Existing safe-area and accessibility suites are useful verification but need no edit.

**Decision**: Exactly three writable AppUI paths. Run both focused layout/safe-area suites for T001; leave the full AppUI and simulator evidence gate to parked MY-1487.

## R7 — Dependency replacement

**Finding**: Multica has no formal dependency field for MY-1487. Its dependency is recorded in issue description/comments and it is already parked in stage 2.

**Decision**: After exact planning PASS, update MY-1487's description to depend on MY-1706 and the reviewed planning revision while preserving its parent, stage, assignee, and backlog status. Historical comments remain immutable evidence.

## R8 — Planning outputs

**Finding**: No data, schema, domain language, cross-layer contract, or architectural decision changes.

**Decision**: Provide spec, plan, research, behavioral contract, quickstart, and tasks. Omit `data-model.md`, ADR, and `CONTEXT.md` changes.

## Unresolved Questions

None. Product behavior, technical approach, scope, actor isolation, mutation surface, and downstream ownership are fixed by repository evidence and the Owner/Team Lead direction.
