# Implementation Plan: TestFlight auto-release after verified main CI

**Branch**: `027-testflight-auto-release` | **Date**: 2026-10-15 | **Spec**: [spec.md](./spec.md)

**Input**: MY-1766 planning version v2; exact product base `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`; marker-only Owner/Team Lead authority recorded in `spec.md`.

## Summary

Convert the manual-only TestFlight workflow into an exact-SHA consumer of successful `CI` push runs on `main`, while retaining bounded manual dispatch. Use one VitalStride concurrency group and only the moving `testflight/last-released` marker. Automatic/manual-default relevance is accumulated from marker to candidate; absence uses empty-tree bootstrap; force bypasses only current-main relevance. The critical lane advances the marker only as its final step and configures no automatic retry/rollback or auxiliary release state. Preserve exact candidate version policy, global build numbering, signing/secrets/safe logging, three-path RepoInfra scope, and explicit Owner approval for `.github/**`.

## Technical Context

**Language/Version**: GitHub Actions YAML; Bash workflow steps; Ruby/Fastlane; Python 3 unittest

**Primary Dependencies**: GitHub `workflow_run`, `GITHUB_TOKEN`, Git history/tag, XcodeGen read-only version input, Fastlane/App Store Connect, existing dynamic profile handoff

**Storage**: Only moving tag `testflight/last-released`; transient workflow outputs and job summary; no product store or auxiliary release refs

**Testing**: Credential-free unittest contract coverage, Ruby syntax, complete RepoInfra gate, Git whitespace/static inspection, post-merge operational evidence

**Target Platform**: GitHub Actions on existing `[self-hosted, vitalstride-mac]`; internal TestFlight

**Constraints**: exact CI SHA; sole marker; no per-SHA history/custom durable queue/cursor/CAS/journal/recovery ref; no new secret; no automatic retry/rollback; `.github/**` Owner approval; exact three implementation paths

**Scale/Scope**: one workflow, one Fastlane lane, one existing regression module, one app/repository, one implementation PR

## Evidence Baseline

| Evidence | Exact observation at product base |
|---|---|
| Repository/base | `LeePepe/VitalStride`; `origin/main == a6e31c6f44797fd95ebe50b96fe2310a3e52d789` |
| CI source | `.github/workflows/ci.yml` has exact workflow name `CI` and runs for `push: main` plus PR/manual sources |
| Release trigger | `.github/workflows/testflight.yml` is manual-only, checks out moving `main`, and defaults `force=false` |
| Runner/concurrency | `[self-hosted, vitalstride-mac]`; group `testflight`; `cancel-in-progress: false` |
| Existing release state | Only `testflight/last-released`; baseline force can bypass its no-new-commit gate |
| Build number | Fastfile queries app-wide TestFlight maximum and adds one |
| Marketing version | Fastfile hardcodes `1.1`; shipping targets declare `1.1`; no label path exists |
| Signing/distribution | Dynamic target profiles, manual Release signing, Apple processing wait, internal group distribution |
| Best-effort baseline | Internal distribution rescue and dSYM continuation can allow later marker movement; v2 deliberately makes reviewed critical phases fail closed |
| Regression baseline | Focused Python suite reports 10 tests passing |
| Full local gate risk | Prior full RepoInfra output contained one failure/one error under Xcode Python 3.9 despite wrapper exit 0; full output must be inspected |
| Owner gate | No tracked CODEOWNERS exists; explicit MY-1766 authority is the fail-closed approval boundary |

## Constitution Check — Before Design

| Gate | Result | Evidence |
|---|---|---|
| Privacy/secrets | PASS | Summaries exclude health/credential/profile/certificate/keychain values |
| Swift/package principles | N/A/PASS | No Swift or product/package change; one dependency-free RepoInfra layer |
| XcodeGen truth | PASS | `project.yml` is read for version only and not edited |
| Development workflow | PASS | Planning-only revision → independent gate → Team Lead; one implementation PR; explicit Owner approval |
| Quality Bar A/J | PASS | Exact allowlist; AI Reviewer content-only; PR Manager owns checks/shipping; Team Lead recovery |

No constitution exception or ADR change is required.

## Research Decisions

See [research.md](./research.md). The selected design uses exact successful `workflow_run` identity, exclusion-first accumulated relevance, empty-tree bootstrap, one moving success marker, one non-cancelling app group without a durable FIFO promise, exact-candidate PR/version policy, final marker ordering, and no automatic retry/rollback or auxiliary durable state.

## State and Contract Design

- [data-model.md](./data-model.md) defines candidate, sole marker, eligibility, version, evidence, and terminal transitions.
- [contracts/testflight-auto-release.md](./contracts/testflight-auto-release.md) fixes event/path/version/marker/release/evidence behavior.
- No product schema, public app API, migration, or second release state is introduced.

## Project Structure

### Planning artifacts

```text
specs/027-testflight-auto-release/
├── checklists/requirements.md
├── contracts/testflight-auto-release.md
├── data-model.md
├── plan.md
├── quickstart.md
├── research.md
├── spec.md
└── tasks.md
```

### Implementation paths

```text
.github/workflows/testflight.yml
fastlane/Fastfile
scripts/tests/test_testflight_freshness.py
```

All implementation paths resolve to dependency-free `RepoInfra`. Planning artifacts are support exclusions.

## Scope Contract

### Files in scope

- `.github/workflows/testflight.yml` — event/exact candidate, marker relation/bootstrap, accumulated classifier, bounded force, version gate, single-group serialization, critical ordering, sole marker update/readback, summaries
- `fastlane/Fastfile` — resolved marketing-version input, build-number output/evidence, strict critical result while preserving signing/profile behavior
- `scripts/tests/test_testflight_freshness.py` — red-first credential-free coverage and preserved baseline assertions

### Files NOT to touch

- `.github/workflows/ci.yml`, every other `.github/**`, and any new workflow
- CODEOWNERS/rulesets/branch protection/reviewer policy/AGENTS
- `project.yml`, generated project, app/package/test/Prototype source/resources/entitlements/contexts
- Other `fastlane/**`, `scripts/**`, tests, security config, planning paths outside this feature
- Developer Portal/ASC configuration beyond existing reviewed lane operations

### Interface impact

- **Public product signatures**: none.
- **Workflow input**: retain boolean manual `force=false`; add completed-`CI` automatic input.
- **Internal contract**: exact candidate, marker relation/baseline, accumulated relevance, exact-candidate PR/version, app-wide build, critical result, final marker confirmation, safe evidence.
- **Durable state**: only `testflight/last-released`; expressly no second state family.
- **Permissions/secrets**: candidate PR/label read and sole marker write/read; existing secrets only.

## Vertical Slices and Task Strategy

### US1 — Exact candidate and marker-range eligibility

Write contract tests first, then add exact automatic source, exact checkout, marker absence/order checks, narrow accumulated classifier, one app group, and safe skip/failure summaries. Cover empty-tree bootstrap, irrelevant→relevant accumulation, failed relevant candidate→later pickup, equality/stale/divergence, deletion/rename/copy, and absence of auxiliary state.

### US2 — Versioned fail-closed lane and final marker

Write version/failure tests first, then resolve the exact candidate PR/label for either source, pass one marketing version to Fastlane, expose the app-wide build number, make the reviewed release phases critical, and update/read back the sole marker only after earlier success. Preserve signing/profile/telemetry behavior and record marker-step failure without inventing state.

### US3 — Bounded manual force

Manual dispatch captures current remote `main`. `force=false` uses marker-range relevance; `force=true` bypasses relevance only. Both retain marker relation, candidate-PR/version, signing, critical-lane, and final-marker gates. A failed unreleased current-main candidate may be picked up by a later manual run.

### Assembled delivery and operational acceptance

Freeze the exact three-file candidate, obtain exact pre-push content review, publish a non-Draft PR, record explicit Owner approval, and let PR Manager own required checks/merge. T005 closes only with first eligible successful production evidence.

## Dependency Graph

```text
T001 US1 exact candidate + marker-range eligibility/concurrency
  └─> T002 US2 version/build + fail-closed lane + final marker
        └─> T003 US3 bounded manual force
              └─> T004 assembled verification/review/Owner-gated PR
                    └─> PR Manager required checks + merge
                          └─> T005 first eligible production success evidence
```

T001–T003 are serialized because files overlap. T004 has no source repair ownership. T005 is execution-only. One goal and one implementation PR cover the feature.

## Verification Strategy

### Credential-free implementation evidence

From repository root:

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
ruby -c fastlane/Fastfile
bash scripts/test-repoinfra.sh
git diff --check
```

Read complete output; focused and full RepoInfra summaries must report zero failures/errors. No local `xcodebuild` or package build/test is warranted for an exact RepoInfra-only diff.

### Static review evidence

- Exact automatic SHA is successful `CI` push/main head; manual SHA is captured current remote `main`.
- Sole marker selects empty-tree bootstrap, normal ancestor range, already-covered skip, or invalid divergence failure.
- Accumulated classifier matches narrow positives/exclusions and record endpoint rules.
- Several skipped/failed candidates write no durable state; later range includes them.
- One group serializes active lanes without in-progress cancellation or custom FIFO state.
- Force bypasses relevance only and cannot bypass already-covered/invalid marker or downstream gates.
- Exact candidate PR alone decides `release:minor`; archive/lookup share one version; build lookup stays app-wide.
- Every earlier critical phase precedes marker mutation; exact marker readback is terminal success; marker failure creates no auxiliary state/retry/rollback.
- Existing profile/signing/secrets/telemetry assertions remain.
- Diff is exactly three implementation paths.

### Post-merge evidence

Record exact candidate/CI SHA, TestFlight run URL, terminal conclusion, marketing version, build number, and confirmed remote marker equal to candidate. Failure is incident-only; a later eligible merge or manual current-main dispatch is the forward path and is not an automatic retry.

## Constitution Check — After Design

| Gate | Result | Design proof |
|---|---|---|
| Scope/layer | PASS | One dependency-free RepoInfra layer; exact three-file allowlist; one goal/PR |
| Behaviour/compatibility/removal | PASS | Spec records product-base behavior and cites Owner authority for every removal/superseded planning state |
| Secrets/privacy | PASS | Existing inputs only; safe evidence schema |
| XcodeGen | PASS | Runtime read/override; no tracked config edit |
| Review/shipping ownership | PASS | Independent content review, explicit Owner approval, PR Manager shipping, Team Lead recovery |
| Verification | PASS | Focused, syntax, full RepoInfra, whitespace/static, and operational surfaces |

## Completion Conditions and Next Actions

Planning readiness requires all eight artifacts to agree, 51 stable IDs traced, no placeholder/clarification, acyclic five-row graph, clean native planning checks, exact blob pins, and AI Reviewer PASS on the exact revision.

Implementation completion requires T001–T004, exact pre-push review, required checks, and explicit Owner approval before merge. Product completion additionally requires successful T005 evidence. A failed-run record never satisfies T005; later pickup may use a new eligible merge or manual current-main run.

The repo mentions `check-tasks-fresh` but contains no executable by that name at this base; this plan does not claim it ran.

## Open Risks

- The local RepoInfra wrapper can return zero while nested output fails under one Python toolchain; full summaries must be read.
- Owner approval for `.github/**` is not machine-enforced at the base; Team Lead/PR Manager must fail closed on missing evidence.
- A final remote marker update may land while acknowledgement/readback is unavailable. The Owner-selected minimal model forbids a journal/lease/recovery ref, so the run fails with safe marker-step evidence and the next run reads the remote marker as sole truth. The plan does not promise proof of an unobservable remote state.
- GitHub concurrency does not promise durable FIFO execution of all pending events. Accumulated ranges and stale-candidate checks preserve correctness without that promise.
- Exact candidate PR—not any earlier PR in the accumulated range—controls `release:minor`; this preserves the reviewed version policy.

## Complexity Tracking

No constitution violation or exceptional cross-layer complexity is accepted.
