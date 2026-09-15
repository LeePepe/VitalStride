# Implementation Plan: App-target required-gate recovery

**Branch**: `024-app-target-gate-recovery` | **Date**: 2026-08-28 | **Spec**: `specs/024-app-target-gate-recovery/spec.md`

**Input**: Feature specification from `specs/024-app-target-gate-recovery/spec.md`

## Summary

Move the App-target test invocation from inline workflow YAML into one RepoInfra-owned shell runner. The runner executes the current non-quarantined suite exactly once, streams the untruncated output while retaining a log, emits explicit terminal evidence, and propagates the real exit status. A deterministic Python regression substitutes a fake test command to lock invocation count, arguments, output visibility, exit behavior, and workflow wiring without running Xcode.

## Technical Context

**Language/Version**: GitHub Actions YAML, Bash available on macOS runners, Python 3 standard library

**Primary Dependencies**: GitHub Actions runner shell, `xcodebuild`, `tee`, Python `unittest`

**Storage**: Ephemeral workflow log only; no product data or persisted schema

**Testing**: `bash scripts/test-repoinfra.sh`; focused Python unittest discovery; Bash syntax check; diff whitespace check

**Target Platform**: GitHub Actions `macos-26` App-target job and local macOS RepoInfra validation

**Project Type**: Repository automation/configuration

**Performance Goals**: A deterministic non-quarantined failure consumes one App-target suite attempt instead of three; local regression runs without a simulator

**Constraints**: Preserve job/check identity, existing command parameters and sole quarantine exclusion; no `continue-on-error`; no product/AppUI/package/ruleset changes; no mutation of the MY-1489 delivery branch

**Scale/Scope**: One required job, one extracted runner, one deterministic regression

## Incident Evidence and Investigation Boundary

- Accepted evidence: run `33089199269`, App-target job `98587660994`, exact head `cb78fe8c70071c11f91bf400b00ef14b7812e771`.
- All three attempts failed `ExercisesJSONTests.fullCatalogSectionDistribution()`; only attempt one also failed `RestCompletedPresenterLifecycleTests.canceledWaiterCannotWakeReplacement()`.
- `.github/workflows/ci.yml` currently excludes the only named quarantine before executing the suite, then retries every remaining failure up to three times. Therefore the repeated catalog assertion was non-quarantined and the retry policy, not failure ownership, is the RepoInfra defect.
- `tail -60` sits in the live pipeline and can withhold progress until enough output arrives. The recovery must stream the full command output through `tee` and emit bounded terminal evidence after completion.
- Root-cause work stops at invocation, observation, retry, and exit propagation. MY-1490 owns catalog expectation correctness; presenter lifecycle behavior, simulator behavior, and the VitalModels patch are excluded.

## Constitution Check

### Before design

- Constitution Principle III and ADR-0019: PASS. All implementation paths belong to the dependency-free RepoInfra layer.
- Principle IV / Quality Bar E: PASS. `project.yml` and generated Xcode artifacts are excluded.
- Quality Bar A: PASS. Exact files are bounded below; MY-1490 and MY-1489 surfaces are excluded.
- Quality Bar I: PASS. The recovery requires a deterministic behavior regression, not a YAML text-only assertion.
- Quality Bar J: PASS. The workflow reports the real required-gate result and does not claim that RepoInfra owns the product-test failure.
- Pipeline Recovery PR-2: PASS. Current nonterminal issue search found no matching recovery scope; tracker creation occurs only after exact-revision review.

### After design

- Layer direction remains acyclic: RepoInfra has no product dependency; invoking AppUI verification does not create one.
- The required check remains unchanged and fail-closed.
- The regression exercises the extracted production runner with a controlled command and also checks workflow wiring, so the feedback loop is deterministic and red-capable.
- No new product interface, quarantine, persisted state, or architecture decision is introduced; no ADR is required.

## Project Structure

### Documentation (this feature)

```text
specs/024-app-target-gate-recovery/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── app-target-gate.md
└── tasks.md
```

### Source Code (repository root)

```text
.github/workflows/ci.yml
scripts/ci/run-app-target-tests.sh
scripts/tests/test_app_target_gate.py
```

**Structure Decision**: Keep workflow orchestration in `ci.yml`, isolate command execution and exit propagation in a shell runner, and place deterministic behavior coverage under the existing auto-discovered RepoInfra Python test suite. `scripts/test-repoinfra.sh` already discovers `scripts/tests/test_*.py`, so it requires no modification.

## Files in Scope

- `.github/workflows/ci.yml`
- `scripts/ci/run-app-target-tests.sh` (new)
- `scripts/tests/test_app_target_gate.py` (new)

## Files NOT to Touch

- `project.yml`
- `VitalStride.xcodeproj/**`
- `VitalStrideTests/**`, especially `VitalStrideTests/Sources/ExercisesJSONTests.swift` owned by MY-1490
- `VitalStride/**`, `VitalStrideMac/**`, `VitalStrideWatch Watch App/**`, `VitalStrideWidgets/**`
- `Packages/**`, including the reviewed VitalModels patch
- `scripts/rulesets/main-protection.json`
- Other workflow files, hooks, review gates, or quarantine definitions
- The MY-1489 delivery workspace/branch and PR #418 head

## Interface Contract

- Internal-only RepoInfra command boundary: `ci.yml` invokes the extracted runner and consumes its exit status.
- The runner preserves the current App-target project, scheme, destination, package-plugin-validation flag, and sole explicit quarantine exclusion.
- The production path has one non-quarantined suite invocation and no whole-suite retry loop.
- The job key/name remain `app` / `App target`; no public product API changes.
- The deterministic test may inject a controlled command through a test-only process boundary, but production defaults remain fixed and fail-closed.

## Dependency Strategy

- `T001` has no implementation prerequisite and may run in parallel with MY-1490.
- MY-1490 exclusively owns the catalog-distribution expectation update and must not be absorbed into `T001`.
- MY-1489 remains blocked until both the reviewed RepoInfra recovery and MY-1490 are merged, after which Team Lead may request one fresh required App-target run on PR #418.
- MY-1489 is unblocked for shipping only when that fresh required App-target check reaches terminal success at the still-reviewed PR head or a newly reviewed descendant head authorized by the normal delivery workflow.

## Verification Strategy

From repository root:

1. Run the focused deterministic regression:
   `python3 -B -m unittest discover -s scripts/tests -p 'test_app_target_gate.py'`
2. Run the complete RepoInfra fast gate:
   `bash scripts/test-repoinfra.sh`
3. Check runner syntax:
   `bash -n scripts/ci/run-app-target-tests.sh`
4. Check patch whitespace:
   `git diff --check`

The implementation task must demonstrate red-green behavior for the deterministic failure fixture: before the production change it exposes repeated/inline behavior or missing runner wiring; after the change it proves one invocation and nonzero propagation.

## Complexity Tracking

No constitutional exception or new layer is required.

