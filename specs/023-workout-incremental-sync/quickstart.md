# Quickstart: MY-1477 implementation and verification

## Preconditions

- Work only in the daemon-provided worktree.
- Read `.specify/memory/constitution.md`, `AGENTS.md`, and `Packages/HealthKitService/CONTEXT.md`.
- Keep the diff within the files declared by `tasks.md`.
- Do not run `xcodebuild`; this is a package-only change.

## Execution Order

1. Complete T023-001 and keep the package gate green.
2. Complete T023-002 after T023-001.
3. In T023-002, add the regression assertions first and run the focused suite to capture the expected failure against the old replacement behavior.
4. Implement reconciliation, range provenance, request-keyed coalescing, and workout generation.
5. Run the focused workout suites.
6. Run the full repository-declared package gate.

## Required Regression Matrix

- Baseline A → empty changes → A remains.
- Baseline A → add B + delete A → only B.
- Existing UUID → changed record → one updated record.
- Repeat the same changes → identical result.
- Same timestamps → UUID tie-breaker is stable.
- Empty process cache with persisted-anchor behavior → baseline requested.
- Default 30-day coverage → wider range fetches a snapshot.
- Explicit range → later default request rebuilds a compatible baseline.
- Different ranges/semantics → no incorrect task coalescing.
- Late cancelled or invalidated work → no stale cache commit.
- Provider error → prior cache remains.

## Focused Verification

From the repository root, use Swift Testing filters appropriate to the final suite names, including the existing workout-cache suite and the new provider-contract suite. Record the red result before the fix and the green result after it.

## Required Layer Gate

Working directory: `Packages/HealthKitService`

```bash
swift build && swift test
```

Acceptance requires exit code 0 for both commands. Do not substitute an AppUI build or simulator test.

## Diff Audit

Before handoff, confirm:

- only the HealthKitService source/tests named in `tasks.md` changed;
- `workoutData(in:)`, `refreshWorkouts(in:)`, and direct `fetchWorkouts(dateRange:)` call shapes remain source-compatible;
- no health values/details were added to logs;
- no unsafe concurrency annotation was introduced;
- no AppUI, schema, WatchConnectivity, generated Xcode project, or project configuration file changed.
