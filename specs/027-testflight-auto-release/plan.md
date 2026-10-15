# Implementation Plan: Minimal automatic TestFlight release after main CI

**Planning version**: v3
**Product base**: `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`
**Planning predecessor**: `73dd9ffd2f7cb1980cbe986d0ea9cd3442ecff85`
**Layer**: `RepoInfra` (`depends_on: []`)
**Authority**: Lead direction `01a13cc2-e475-758b-b825-a9f622ca117a`; Team Lead handoff `01a13cc7-9937-74fb-bdc7-4f9a10aaa98d`

## Summary

Add the smallest automatic orchestration around the existing TestFlight lane:

1. accept only a successful completed `CI` `workflow_run` for a push to `main`;
2. bind the run to its verified `head_sha`;
3. classify `git diff testflight/last-released..head_sha` against the accepted app paths;
4. skip an irrelevant range without marker mutation;
5. invoke the existing release lane for a relevant range;
6. update the sole marker only after upload succeeds.

Use one non-cancelling app concurrency group and job-level `contents: write`. Add no auxiliary release state, CAS boundary, shadow-policy suite, automatic retry, or rollback.

## Technical context

| Item | Decision |
|---|---|
| Runtime | GitHub Actions YAML and existing shell steps |
| Existing release implementation | `fastlane ios beta`; unchanged |
| Automatic candidate | verified `github.event.workflow_run.head_sha` |
| Upstream source | workflow `CI`, completed successfully, event `push`, branch `main` |
| Relevance baseline | remote `testflight/last-released` |
| Relevance range | `testflight/last-released..candidate` |
| Durable release state | only `testflight/last-released` |
| Serialization | one app-scoped group, `cancel-in-progress: false` |
| GitHub permission | job-level `contents: write` |
| Feature-specific verification | classifier unit tests; `actionlint` workflow lint |
| Mandatory repository gate | `bash scripts/test-repoinfra.sh`; inspect full output for nested failures/errors |
| External lint prerequisite | executor provides `actionlint`; the pinned repository has no native workflow linter |
| Real upload/tag mutation | excluded from planning and local verification |

## Constitution and repository checks

- Constitution I–VII: no product, privacy, concurrency, package, XcodeGen, AI, localization, or platform-feature change.
- Repo ownership: all ceiling paths map to dependency-free `RepoInfra`.
- Planning boundary: artifacts contain contracts and evidence, not implementation code.
- PR boundary: one goal/one PR; PR-required delivery remains in force.
- Owner boundary: an explicit Owner approval for `.github/workflows/testflight.yml` remains mandatory and cannot be replaced by AI Reviewer PASS or CI.
- Verification boundary: classifier unittest and `actionlint` are the only feature-specific checks; the existing mandatory `bash scripts/test-repoinfra.sh` RepoInfra gate remains unchanged. No xcodebuild, SwiftPM, standalone Ruby syntax, Fastlane execution, upload, signing/profile, or production-run feature gate is added.

## Existing behaviour evidence

At the product base:

- `.github/workflows/ci.yml` names the upstream workflow `CI` and runs it for pushes to `main`.
- `.github/workflows/testflight.yml` is manual-only, checks out moving `main`, compares only HEAD with the marker, invokes `fastlane ios beta`, and moves the marker after the lane.
- The current workflow already has one non-cancelling concurrency group, but `contents: write` is workflow-level rather than job-level.
- `fastlane/Fastfile` already builds/signs and uploads the binary. It therefore stays unchanged for this minimal revision.
- The repository does not provision a dedicated workflow linter; `actionlint` is an executor prerequisite for the required semantic workflow-lint evidence.

## Owned paths

### Implementation ceiling

- `.github/workflows/testflight.yml`
- `fastlane/Fastfile`
- `scripts/tests/test_testflight_freshness.py`

### Expected minimal change set

- `.github/workflows/testflight.yml`
- `scripts/tests/test_testflight_freshness.py`

`fastlane/Fastfile` is a read-only compatibility surface in v3. Any need to edit it invalidates this task graph and returns to Team Lead/Planner review; it does not authorize silent expansion.

### Excluded paths

All other workflow, Fastlane, script/test, app, package, AppUI, Prototype, project, generated, policy, CODEOWNERS, ruleset, secret, and signing paths are excluded.

## Design

### Automatic source gate

The workflow event supplies the immutable candidate. Reject any payload that is not the exact successful-main CI shape before checkout or release. Checkout and subsequent commands use the captured candidate, never moving `main`.

### Marker-range classifier

Fetch full history and tags. Resolve the sole marker as an ancestor commit of the candidate, then classify NUL-safe records in `marker..candidate`. Missing/invalid/non-ancestor marker state fails closed. Irrelevant ranges skip without state mutation; because the marker remains unchanged, later candidates naturally include the accumulated range.

The accepted path predicates and exclusion precedence live in the contract. The classifier unit tests are the only behavior-test surface.

### Existing lane and marker ordering

Call the existing `fastlane ios beta` lane without modifying Fastfile. The marker command is ordered after the lane and targets the captured candidate. Any failure before that command leaves the marker unchanged. The workflow adds no automatic retry, rollback, second marker, per-SHA record, queue/cursor, CAS/lease, journal, pending/resolved state, or recovery ref.

### Concurrency and permission

Retain one stable app-scoped concurrency group with `cancel-in-progress: false`. Move `contents: write` to the release job. Add no other GitHub permission.

## Verification strategy

From the repository root, the complete feature-specific verification is:

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
actionlint .github/workflows/testflight.yml
```

The test module must be trimmed to classifier-focused coverage. `actionlint` is a named executor prerequisite, not an existing repository-native gate. Both commands are credential-free and must perform no GitHub write, signing, upload, App Store Connect request, or tag mutation.

The repository-level RepoInfra gate remains independently mandatory:

```bash
bash scripts/test-repoinfra.sh
```

Read its full output and require zero failures/errors; exit code alone is insufficient. This repository gate supplements rather than expands the two feature-specific checks and does not reintroduce any v2 shadow-policy acceptance.

Normal exact-revision identity checks, diff-path inspection, and review metadata are delivery evidence, not additional product test suites.

## Task graph

```text
T001 minimal workflow + classifier implementation
  -> T002 freeze/check + publish non-Draft PR + three-way identity proof + exact review + post-PASS identity re-proof
       -> PR Manager required checks and merge
```

- T001 owns the only implementation edits.
- T002 freezes and verifies the candidate, commits/pushes it into the single non-Draft PR, proves local `HEAD` = remote branch OID = PR `headRefOid`, and only then requests exact-candidate review for that published SHA.
- After PASS, T002 re-proves the same three-way identity before handing that SHA to PR Manager. T002 performs no source repair; a finding returns to T001, and any content change requires a fresh published SHA and review.
- Explicit Owner approval for `.github/workflows/testflight.yml` remains a separate pre-merge gate; it does not gate candidate-PR publication or substitute for AI review.
- No production-execution/evidence task exists in v3.
- Team Lead alone schedules implementation after planning PASS.

## Preserved candidate reuse

The preserved delivery workspace remains:

- workdir: `/Users/lee/multica_workspaces/my-39e1cf97c2a4/my-1766-a189e279e80a/workdir/VitalStride`
- branch: `agent/fullstack-engineer/a189e279e80a`
- current base: `73dd9ffd2f7cb1980cbe986d0ea9cd3442ecff85`
- local changes: only `.github/workflows/testflight.yml` and `scripts/tests/test_testflight_freshness.py`

This v3 planning commit is published as a planning-only descendant of that base. After Team Lead dispatches reuse, Fullstack must revalidate registered identity, fetch the exact reviewed v3 revision, prove the v2→v3 diff contains planning paths only, prove the local candidate still contains exactly the two implementation paths, and fast-forward the same branch/workspace to the reviewed revision. No reset, clean, alternate checkout, copying, or silent conflict resolution is allowed. A non-fast-forward or overlap returns to Team Lead recovery.

## Risks and controls

| Risk | Control |
|---|---|
| A later moving `main` SHA is released | capture and reuse `workflow_run.head_sha` |
| Irrelevant commits suppress a later app release | diff from unchanged last-success marker |
| Invalid marker enters release | fail closed before lane |
| Upload failure advances release state | marker step ordered after lane success |
| Overlapping runs cancel a release | one group with cancellation disabled |
| Workflow gains broad write authority | job-level `contents: write` only |
| v2 complexity returns through feature tests | only classifier tests and workflow lint are feature-specific; mandatory RepoInfra remains a separate repository gate |
| Preserved candidate is lost | reuse exact registered workspace by fast-forward only |

## Completion conditions

Planning is ready only when:

- all eight artifacts express this two-task minimal graph without stale v2 requirements and preserve the mandatory RepoInfra repository gate;
- traceability covers every active US/AC, FR, RB, and SC identifier;
- an exact published revision has a recorded tree and artifact blob SHAs;
- independent AI Reviewer verdict is PASS for that exact revision;
- the five existing child rows are reconciled only after PASS, with the two surviving rows parked and three superseded rows cancelled;
- Team Lead receives the reviewed evidence and safe reuse path.

Implementation completion is outside Planner ownership.
