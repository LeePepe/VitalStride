# Feature Specification: App-target required-gate recovery

**Feature Branch**: `024-app-target-gate-recovery`

**Created**: 2026-08-28

**Status**: Draft

**Input**: Recover the required App-target gate after run `33089199269`, job `98587660994`, retried the same non-quarantined catalog failure three times at reviewed head `cb78fe8c70071c11f91bf400b00ef14b7812e771`.

## User Scenarios & Testing

### User Story 1 - Fail fast with observable gate evidence (Priority: P1)

As the delivery owner, I need the required App-target gate to run the non-quarantined suite once, report its progress and failure evidence continuously, and return the real terminal result so a deterministic failure is not mislabeled or delayed by whole-suite retries.

**Why this priority**: PR #418 is blocked even though its package and review gates are green. The current retry policy spent three full attempts on the same deterministic catalog assertion and obscured the distinction between the product-test failure and the RepoInfra retry defect.

**Independent Test**: A deterministic, agent-runnable workflow contract substitutes a controlled test command for the expensive App-target invocation and proves invocation count, output visibility, arguments, and exit propagation without a simulator.

**Acceptance Scenarios**:

1. **Given** the required non-quarantined suite returns nonzero, **When** the gate runner executes, **Then** it invokes that suite exactly once, streams progress and failure evidence, and terminates the required job with failure.
2. **Given** the required non-quarantined suite returns zero, **When** the gate runner executes, **Then** it invokes that suite exactly once and terminates the required job successfully.
3. **Given** the explicit existing quarantine remains configured, **When** the gate command is assembled, **Then** no additional test is skipped and no whole-suite retry is introduced.
4. **Given** the workflow is inspected after the change, **When** GitHub evaluates the job, **Then** the job and required-check identity remain `app` / `App target`, with no fail-open or `continue-on-error` path.

### Edge Cases

- A non-quarantined failure occurs alongside a timing-sensitive failure: the first nonzero suite result remains terminal; RepoInfra does not infer product-test ownership from log text.
- The test command exits before producing a normal XCTest summary: the exit code still propagates and the available output remains visible.
- The explicit quarantined-test identifier changes or an additional quarantine is proposed: that is a separate reviewed change and is not silently absorbed by this recovery.
- MY-1490 has not yet updated the catalog-distribution expectation: this recovery may merge independently, but PR #418 cannot be declared unblocked until both blockers land and a fresh required gate succeeds.

## Requirements

### Functional Requirements

- **FR-001**: The required App-target job MUST invoke the non-quarantined App-target suite no more than once per workflow run.
- **FR-002**: Any nonzero result from that suite MUST immediately become the terminal job result; the workflow MUST NOT retry the entire suite under the quarantine label.
- **FR-003**: The gate MUST preserve the current project, scheme, simulator destination, package-plugin-validation flag, and sole explicit quarantine exclusion.
- **FR-004**: The gate MUST stream command progress to the GitHub job log and retain a readable terminal success or failure signal; output truncation MUST NOT hide progress while the command is running.
- **FR-005**: The workflow MUST retain the `app` job and `App target` check name, remain required by the existing repository policy, and contain no fail-open behavior.
- **FR-006**: A deterministic local regression MUST prove one invocation on failure, failure propagation, one invocation on success, preserved command arguments/quarantine, visible progress/failure sentinels, and workflow-to-runner wiring.
- **FR-007**: RepoInfra validation MUST include the new regression through the existing `bash scripts/test-repoinfra.sh` entry point.
- **FR-008**: The change MUST NOT modify product code, app tests, package code, `project.yml`, generated Xcode artifacts, ruleset requirements, or the reviewed MY-1489/PR #418 branch.
- **FR-009**: The recovery MUST treat MY-1490 as the sole owner of the catalog-distribution expectation change and MUST NOT duplicate that work.

## Scope Boundaries

### Root-cause investigation boundary

The investigation covers only how the RepoInfra workflow launches, observes, retries, and propagates the App-target test result. It may prove that the current runner retries every executed failure even though the named quarantine is excluded. It does not diagnose or change the catalog-distribution assertion, the one-off presenter timing failure, simulator/product behavior, or the VitalModels patch.

### Non-goals

- Fixing `ExercisesJSONTests.fullCatalogSectionDistribution()`; MY-1490 owns that expectation.
- Fixing `RestCompletedPresenterLifecycleTests.canceledWaiterCannotWakeReplacement()` or adding a new quarantine.
- Weakening, renaming, bypassing, or removing the required App-target gate.
- Re-running, merging, or modifying PR #418 before its independent blockers are resolved.
- Changing `project.yml`, the generated Xcode project, product sources, app tests, or packages.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The deterministic failure fixture records exactly one test-command invocation and the gate returns nonzero.
- **SC-002**: The deterministic success fixture records exactly one test-command invocation and the gate returns zero.
- **SC-003**: The regression proves live progress and terminal failure markers are present and that the production command retains all required arguments plus only the existing quarantine exclusion.
- **SC-004**: `bash scripts/test-repoinfra.sh` and the focused deterministic workflow regression complete with zero failures.
- **SC-005**: The workflow still exposes the required `App target` check with no `continue-on-error`, whole-suite retry loop, or additional skipped test.

## Assumptions

- Run `33089199269` and job `98587660994` are accepted incident evidence; the planning task does not re-run them.
- The explicit `OverviewHealthSnapshotTests/loadAllMetrics` exclusion remains the current accepted quarantine boundary; changing that boundary requires separate authority.
- RepoInfra recovery and MY-1490 can be implemented in parallel, but both must merge before Team Lead requests a fresh PR #418 App-target result.

