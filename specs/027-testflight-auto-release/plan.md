# Implementation Plan: TestFlight auto-release after verified main CI

**Branch**: `027-testflight-auto-release` | **Date**: 2026-10-15 | **Spec**: [spec.md](./spec.md)

**Input**: MY-1766 revision 3 and the exact planning base `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`.

## Summary

Convert the existing manual-only internal TestFlight workflow into an exact-SHA consumer of successful `CI` push runs on `main`, while keeping bounded manual dispatch. The workflow classifies accumulated app-relevant changes, claims each SHA once, serializes releases on the Owner's `vitalstride-mac`, derives one runtime marketing version and a globally monotonic build number, fails closed without retry/rollback, and records safe evidence. Implementation remains one RepoInfra PR and requires explicit Owner approval because it changes `.github/workflows/testflight.yml`.

## Technical Context

**Language/Version**: GitHub Actions YAML; Bash in workflow steps; Ruby/Fastlane on the self-hosted macOS runner; Python 3 unittest regression coverage

**Primary Dependencies**: GitHub `workflow_run`, `GITHUB_TOKEN`, git moving tags, XcodeGen, Fastlane/App Store Connect API, existing dynamic provisioning-profile handoff

**Storage**: Git tags `testflight/last-attempted` and `testflight/last-released`; transient workflow outputs and job summary; no product data store

**Testing**: `unittest` static/contract coverage, Ruby syntax validation, complete RepoInfra gate, Git whitespace validation; post-merge production evidence

**Target Platform**: GitHub Actions plus the existing `[self-hosted, vitalstride-mac]` runner; internal TestFlight

**Project Type**: Mobile-app repository release automation

**Performance Goals**: One serialized release at a time; no redundant archive for ineligible or already-attempted SHAs

**Constraints**: Exact CI SHA; no new secret; no automatic retry/rollback; no same-SHA second attempt; `.github/**` Owner approval; no implementation outside three allowlisted RepoInfra files

**Scale/Scope**: One workflow, one Fastlane lane, one existing regression module, one app/repository

## Evidence Baseline

| Evidence | Exact observation at planning base |
|---|---|
| Repository/base | `LeePepe/VitalStride`, local `HEAD == origin/main == a6e31c6f44797fd95ebe50b96fe2310a3e52d789`; clean task branch `agent/planner-lead/7c7a7ca17d09` |
| CI source | `.github/workflows/ci.yml` has exact workflow name `CI` and triggers PR, `push: main`, and manual runs |
| Release trigger | `.github/workflows/testflight.yml` is `workflow_dispatch`-only, checks out moving `main`, and defaults `force=false` |
| Runner/concurrency | `[self-hosted, vitalstride-mac]`; group `testflight`; `cancel-in-progress: false` |
| Existing markers | Only `testflight/last-released`; force can bypass its equality guard |
| Build number | Fastfile queries the app-wide TestFlight maximum and adds one |
| Marketing version | Fastfile hardcodes `1.1`; shipping targets in `project.yml` declare `1.1`; no `release:minor` path exists |
| Signing/distribution | Dynamic target-specific profiles, manual Release signing, Apple processing wait, explicit internal-group distribution |
| Regression baseline | `python3 -B -m unittest scripts.tests.test_testflight_freshness` reports 10 tests, all passing |
| Full local gate risk | `bash scripts/test-repoinfra.sh` printed 29 tests with one failure and one error under Xcode Python 3.9 (`str | None`, missing `tomllib`) despite exit 0; this is baseline environment/tooling evidence, not a passing claim |
| Owner gate | No tracked `CODEOWNERS` exists and current ruleset evidence does not machine-enforce code-owner approval; MY-1766's explicit Owner decision is authoritative |

## Constitution Check — Before Design

| Gate | Result | Evidence |
|---|---|---|
| Principle I privacy | PASS | Release summaries exclude health values, secrets, keys, profiles, and signing material |
| Principle II concurrency | N/A | No Swift code |
| Principle III package priority | PASS | No product logic or package change; release automation remains RepoInfra |
| Principle IV XcodeGen truth source | PASS | `project.yml` is read for version input but is not edited; runtime override is ephemeral |
| Principles V–VII | PASS/N/A | Existing telemetry inputs and internal TestFlight scope are preserved; no UI/platform feature change |
| Development Workflow | PASS | One planning revision, independent spec gate, one implementation PR, required CI, Owner approval for `.github/**` |
| Quality Bar A scope | PASS | Implementation allowlist is exact and layer-owned |
| Quality Bar J | PASS | AI Reviewer reviews content; PR Manager owns required checks/shipping evidence; Team Lead owns recovery/escalation |

No constitution exception or ADR change is required.

## Research Decisions

See [research.md](./research.md). The selected design uses `workflow_run` rather than `push`, exact CI SHA rather than moving `main`, a workflow-local accumulated path classifier rather than trigger-time `paths`, two moving markers rather than an unsafe single post-upload marker, and one environment/output marketing-version contract rather than editing `project.yml` on the runner.

## State and Contract Design

- [data-model.md](./data-model.md) defines candidate, marker, eligibility, version, attempt, and evidence states.
- [contracts/testflight-auto-release.md](./contracts/testflight-auto-release.md) is the exact event/path/version/marker/release/evidence contract.
- No product schema, public app API, or data migration is introduced.

## Project Structure

### Documentation (this feature)

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

### Source Code (implementation)

```text
.github/workflows/testflight.yml
fastlane/Fastfile
scripts/tests/test_testflight_freshness.py
```

**Structure Decision**: All implementation paths belong to `RepoInfra` under [RepoInfra/CONTEXT.md](../../RepoInfra/CONTEXT.md). Planning files are support exclusions and become the immutable reviewed baseline; no AppUI/package layer is scheduled.

## Scope Contract

### Files in scope

- `.github/workflows/testflight.yml` — event contract, exact candidate, path/marker/version gate, attempt/success sequencing, summaries, critical-step behavior
- `fastlane/Fastfile` — resolved marketing-version input, build-number output/evidence, strict distribution result
- `scripts/tests/test_testflight_freshness.py` — red-first credential-free coverage for the complete release contract while preserving signing/profile assertions

### Files NOT to touch

- `.github/workflows/ci.yml`, every other `.github/**` file, and any new workflow
- `CODEOWNERS`, repository rulesets, branch protection, agent/reviewer policy, or `AGENTS.md`
- `project.yml`, `VitalStride.xcodeproj/**`, app/package/test/Prototype source, resources, entitlements, bundle identifiers, and contexts
- Other `fastlane/**`, `scripts/**`, tests, secrets/security configuration, or planning artifacts outside `specs/027-testflight-auto-release/**`
- Developer Portal/App Store Connect configuration except the existing runtime operations of the reviewed TestFlight lane

### Interface impact

- **Public product signatures**: none.
- **Workflow input**: retain `workflow_dispatch.inputs.force: boolean = false`; add automatic completed-`CI` input through `workflow_run`.
- **Workflow/Fastlane internal contract**: exact candidate SHA, one resolved marketing version, one globally monotonic build number, attempt/success markers, and safe job-summary fields.
- **GitHub permissions**: retain tag-write authority and add only the read authority required to resolve the exact associated PR/label; no new secret or broad repository writer.
- **Operational evidence**: exact SHA, run URL, terminal conclusion, marketing/build versions, and marker state; never credentials or signing material.

## Vertical Slices and Task Strategy

### Slice US1/US3 — Exact candidate and bounded eligibility

Implement contract tests first, then add the successful-main-CI trigger, exact-SHA checkout, accumulated path classifier, attempt/success guards, bounded force behavior, concurrency, and safe skip/failure summaries. This slice owns only RepoInfra paths and is independently testable without Apple credentials.

### Slice US2 — Versioned fail-closed release

Extend the same regression module first, then feed one project-derived/label-adjusted marketing version into Fastlane, expose the app-wide build number, make distribution/dSYM phases release-critical, and preserve all signing/profile/telemetry behavior. This slice is sequential after US1 because it edits the same three files.

### Operational acceptance — Reviewed PR and first eligible merge

After exact pre-push review and required CI, the `.github/**` PR cannot merge until explicit Owner approval is recorded. After merge, the first eligible successful main CI run supplies MY-1766 evidence. This is external-state acceptance, not a planning or credential-free implementation test.

## Dependency Graph

```text
T001 US1/US3 exact-SHA eligibility + marker contract (RepoInfra)
  └─> T002 US2 version/output/fail-closed lane contract (RepoInfra)
        └─> T003 assembled candidate verification + exact review + Owner-gated PR
              └─> required CI / PR Manager shipping
                    └─> T004 first eligible main-run evidence on MY-1766
```

- T001 and T002 are serialized because their owned file sets overlap.
- T003 is verification/publication-only and may not repair content; failures route to T001/T002 by path.
- T004 performs no repository edit and cannot be claimed before the reviewed implementation merges with explicit Owner approval.
- One goal and one implementation PR cover the complete feature.

## Verification Strategy

### Credential-free implementation evidence

From repository root:

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
ruby -c fastlane/Fastfile
bash scripts/test-repoinfra.sh
git diff --check
```

Acceptance requires reading the full output, not trusting exit code alone: focused tests and the RepoInfra test summary must report zero failures/errors. The baseline Python-toolchain failures above are not authorized to be hidden, counted as success, or repaired outside the allowlist; unresolved environment/infra evidence routes through Team Lead/PR Manager recovery.

No `xcodebuild` or package build/test is warranted while the implementation diff remains RepoInfra-only.

### Static review evidence

- Exact candidate checkout uses `workflow_run.head_sha` for automatic runs.
- Source event is successful `push` on `main` from exact workflow `CI`.
- Path allowlist/exclusions, force boundary, and both marker transitions match the contract.
- Marketing version has one source and is reused by archive and post-upload lookup; build-number query remains app-wide.
- No release-critical step has `continue-on-error`, rescue-and-continue, or retry behavior.
- Existing profile/signing assertions remain present and passing.
- Diff contains only the three implementation paths.

### Post-merge operational evidence

For the first eligible candidate: exact main/CI SHA, TestFlight run URL, terminal conclusion, marketing version, build number, and remote values of both release markers. The evidence must show one run/upload for that SHA and contain no secret or signing artifact.

## Constitution Check — After Design

| Gate | Result | Design proof |
|---|---|---|
| Scope/layer ownership | PASS | One RepoInfra layer; exact three-file allowlist; one goal/PR |
| Existing behavior / compatibility / removal | PASS | Spec carries explicit sections and every removal cites a Decision/Owner authority |
| Secrets/privacy | PASS | Existing secrets only; safe summary/evidence schema |
| XcodeGen/config truth | PASS | Runtime version override reads but does not change `project.yml` |
| Review/shipping ownership | PASS | AI Reviewer content review, Owner `.github/**` approval, PR Manager CI/shipping, Team Lead recovery remain separate |
| Verification | PASS | Focused, syntax, full RepoInfra, whitespace, static traceability, and operational evidence surfaces are explicit |

No post-design constitution violation remains.

## Completion Conditions and Next Actions

Planning readiness requires complete artifacts, no placeholders/`NEEDS CLARIFICATION`, complete AC/task traceability, acyclic dependencies, native prerequisite success, `git diff --check`, exact planning blob SHAs, and AI Reviewer PASS on the exact planning revision.

Implementation completion requires T001–T003, exact pre-push review, required CI, and explicit Owner approval before merge. Product outcome completion additionally requires T004 evidence from the first eligible main candidate.

The repository documents `check-tasks-fresh` as a desired design-time gate but contains no executable by that name at the planning base. This plan does not claim it ran; exact blob SHAs plus independent review provide freshness evidence.

## Open Risks

- The current local RepoInfra script can return exit 0 while its nested test output reports failures under the Xcode Python 3.9 environment. Implementers and shippers must inspect the test summary and route pre-existing/toolchain failures rather than masking them.
- `.github/**` Owner approval is not machine-enforced by tracked CODEOWNERS at the planning base. Team Lead/PR Manager must fail closed on missing explicit Owner approval.
- GitHub exact-SHA-to-PR association is expected to be unique under protected PR-only main; ambiguity is a designed pre-attempt failure, not a guessed no-label state.

## Complexity Tracking

No constitution violation or exceptional cross-layer complexity is accepted.
