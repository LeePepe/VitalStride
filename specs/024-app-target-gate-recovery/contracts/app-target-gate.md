# Contract: Required App-target test gate

## Required identity

- Workflow job key: `app`
- Required check name: `App target`
- The recovery must not rename, remove, bypass, or mark this job fail-open.

## Invocation contract

- The non-quarantined suite runs exactly once per job.
- The invocation retains the existing project, scheme, simulator destination, package-plugin-validation flag, and sole explicit quarantine exclusion.
- The runner introduces no additional `skip-testing` selector.
- A nonzero exit is terminal and propagates from runner to workflow.
- A zero exit is terminal success.

## Observability contract

- The job log shows an explicit start marker before the expensive command begins.
- Command output streams while the command is running and is retained in the job log.
- Both success and failure paths close any opened GitHub Actions log group.
- Failure output includes an explicit terminal marker and a bounded readable error summary.
- Observability logic must not replace or mask the original command exit status.

## Deterministic regression contract

The focused RepoInfra test uses a controlled command and proves:

1. failing command → exactly one invocation and nonzero runner result;
2. successful command → exactly one invocation and zero runner result;
3. progress and terminal markers remain visible;
4. production arguments and sole quarantine selector remain intact;
5. `ci.yml` invokes the runner from the unchanged `app` / `App target` job;
6. no whole-suite retry loop or `continue-on-error` path remains.

## Ownership boundary

- MY-1490 owns `ExercisesJSONTests.fullCatalogSectionDistribution()` expectation changes.
- This contract does not classify, modify, or quarantine product tests.
- `scripts/rulesets/main-protection.json` remains unchanged; its existing `App target` requirement continues to apply.

