# Research: App-target required-gate recovery

## Evidence

- GitHub Actions run `33089199269`, App-target job `98587660994`, and reviewed head `cb78fe8c70071c11f91bf400b00ef14b7812e771` are the accepted incident anchors.
- The job completed failure after three full-suite attempts.
- `ExercisesJSONTests.fullCatalogSectionDistribution()` failed on every attempt; `RestCompletedPresenterLifecycleTests.canceledWaiterCannotWakeReplacement()` appeared only on the first.
- Package and review gates were green. PR #418 remains open and blocked.
- In `ci.yml`, the only named quarantine is excluded from every executed suite. The surrounding loop nevertheless retries every nonzero suite result three times.
- The output pipeline ends with `tail -60`, which can make long-running progress appear stalled.

## Decision 1: Extract a testable runner

**Decision**: Move the App-target invocation and terminal-status handling to `scripts/ci/run-app-target-tests.sh`; keep workflow setup and required job identity in `ci.yml`.

**Rationale**: A real shell boundary can be exercised with a fake test command, so invocation count, arguments, output, and exit propagation are behaviorally tested. Leaving the logic inline would encourage fragile YAML text assertions or require an expensive simulator loop.

**Alternatives considered**:

- Keep the inline block and add regex assertions against YAML. Rejected because it cannot prove runtime exit propagation or invocation count.
- Parse XCTest logs to decide whether a failure is flaky and retry conditionally. Rejected because product ownership cannot be inferred reliably from log strings, and the named quarantine is already excluded.
- Continue retrying the whole suite with a lower attempt count. Rejected because any replay of a non-quarantined failure violates the recovery contract.

## Decision 2: One fail-closed non-quarantined invocation

**Decision**: Execute the current non-quarantined suite once. Preserve the sole existing quarantine exclusion but add no skipped tests and no retry loop.

**Rationale**: Every test that actually runs is outside the explicit quarantine. Its nonzero result is therefore required-gate evidence and must be terminal. This removes the false “flake quarantined via retry” classification while preserving the accepted quarantine boundary.

## Decision 3: Stream rather than tail the live pipeline

**Decision**: Preserve the full stream through `tee`, emit explicit start and terminal markers, and print a bounded failure summary after the command returns.

**Rationale**: GitHub job logs already retain streamed output. Removing `tail` keeps progress observable; a bounded summary still makes the decisive errors easy to find.

## Decision 4: Keep MY-1490 parallel and external

**Decision**: Treat MY-1490 and RepoInfra recovery as parallel blockers for MY-1489.

**Rationale**: MY-1490 owns the catalog-distribution expectation in AppUI tests. RepoInfra owns only execution policy. Serializing implementation is unnecessary, but a successful fresh PR #418 gate requires both changes to have landed through their own reviewed delivery paths.

## No open clarification

The owner and Team Lead supplied the required failure semantics, scope boundary, dependency owner, and non-weakening constraint. No product decision remains for planning.

