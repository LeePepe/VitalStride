# Implementation Plan: TestFlight in-run profile reuse

**Branch**: `026-testflight-profile-reuse` | **Date**: 2026-10-13 | **Spec**: `specs/026-testflight-profile-reuse/spec.md`

**Input**: Feature specification from `specs/026-testflight-profile-reuse/spec.md`

## Summary

Within the AppUI task, first reconcile the approved base by excluding support-only `VitalStride/CONTEXT.md` from target resources in `project.yml`, then replace the two fixed Release profile display names with a target-specific two-value signing interface. XcodeGen produces synchronized evidence only; no generated project or context file is hand-edited. The RepoInfra task resolves the two canonical in-run names, validates and shell-escapes them for archive, reuses them for export, and extends the credential-free PR regression. Recovery publishes clean layer-scoped replacement history, while shipping waits for MY-1675 / PR #442 and a fresh real `codex-review-target` result.

## Technical Context

**Language/Version**: Ruby/Fastlane on the self-hosted macOS release runner; YAML/XcodeGen; Python 3 standard-library `unittest`

**Primary Dependencies**: Fastlane actions already used by `fastlane/Fastfile`, Ruby `Shellwords`, XcodeGen, Xcode build settings, GitHub Actions

**Storage**: No product persistence; profile names exist only for the release process lifetime

**Testing**: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; XcodeGen regeneration; unsigned generic-iOS Release build; required PR checks

**Target Platform**: Pull-request CI on `macos-26` and the manual `vitalstride-mac` TestFlight runner

**Project Type**: Cross-layer app build configuration plus repository release automation

**Performance Goals**: No extra ASC fetch, archive, or workflow job; static regression remains within the existing fast RepoInfra gate

**Constraints**: Preserve both `force: true` fetches, target distinction, manual Release/Automatic Debug signing, unsigned builds, all workflow freshness/upload behavior, and secret non-disclosure; do not perform a real upload without explicit Owner consent

**Scale/Scope**: One AppUI baseline exclusion plus two target-specific profile substitutions, two bundle identifiers, one release lane, one existing static-test module, one generated project sync, one forward-only replacement PR, and one external trusted-review shipping dependency

## Evidence Baseline

- Base revision: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- Reviewed planning predecessor: `b26401eb2aabd0c41e412ffb904b270e67109650`; this revision repairs it forward-only on `agent/planner-lead/141eba4213fc`.
- At the base, `project.yml` excludes only `*.entitlements` from the `VitalStride` source root, so XcodeGen can add support-only `VitalStride/CONTEXT.md` to target resources. Root `CONTEXT.md` classifies `**/CONTEXT.md` as support exclusions. DEC-026-005 therefore makes its `project.yml` exclusion the T001 baseline-reconciliation component.
- `fastlane/Fastfile` already fetches and installs the app and widget profiles separately with `force: true`.
- Export mapping already consults `sigh_com.leepepe.vitalstride_appstore_profile-name` and `sigh_com.leepepe.vitalstride.widgets_appstore_profile-name`, but falls back to action return values.
- `project.yml` Release configuration contains the two fixed display names that currently control archive selection.
- `scripts/tests/test_testflight_freshness.py` already locks the manual workflow, force/new-commit gate, `main` checkout, and non-cancelling release behavior.
- `scripts/test-repoinfra.sh` auto-discovers `scripts/tests/test_*.py`, and `.github/workflows/ci.yml` invokes it from the PR-required `Lint & policy` job.
- The prior repair produced an observed `99/7` generated-project diagnostic after excluding `VitalStride/CONTEXT.md` and applying the two profile substitutions. That numstat is evidence, not the normative contract; the required result is the exclusion, the two target-correct substitutions, no unrelated generated drift, and same-executable idempotency.
- Owner-authorized recovery preserves PR #441 unchanged and publishes a replacement from the base in the preserved workspace with separate AppUI and RepoInfra commits and no force-push.
- MY-1675 / PR #442 is the shipping prerequisite. Its one-time bootstrap is bound to its exact head (evidence head at planning time: `a7a74b33f1f8f8c12a15b491b04ceb083c2a4704`) and is not reusable by MY-1660.

## Constitution Check

### Before design

- Constitution Principle IV / Quality Bar E: PASS. The `VitalStride/CONTEXT.md` exclusion and both target signing substitutions are explicit `project.yml` truth-source edits; the tracked Xcode project is regenerated only as synchronized output.
- Constitution Principle III and ADR-0018/0019: PASS. T001 remains AppUI-owned and produces one AppUI commit; T002 remains RepoInfra-owned and produces one RepoInfra commit. The generated project, planning artifacts, and shipping evidence acquire no layer ownership.
- Quality Bars A and I: PASS. Exact paths and exclusions are declared below, and the defect receives PR-time deterministic regression coverage.
- Quality Bar J: PASS. Required CI state belongs to PR Manager; the content plan does not make AI Reviewer responsible for CI supervision.
- Constitution Development Workflow / ADR-0021: PASS. Planner publishes an exact planning revision; no implementation starts before AI Reviewer and Team Lead approval.
- Secret/privacy posture: PASS. Tests consume source text and representative non-secret names only; no credentials, profile contents, certificates, or HealthKit values are introduced.

### After design

- The dependency graph is acyclic: AppUI establishes the two-key interface; RepoInfra consumes it; credential-free integration verification depends on both; shipping additionally depends on the post-#442 trusted-review proof; Owner-controlled production validation depends on reviewed merge plus explicit consent.
- AppUI baseline reconciliation precedes evaluation of the two profile substitutions inside T001; it changes only the `project.yml` exclusion and synchronized generated evidence, not support-document or source content.
- The interface is deep and local: two target-specific values determine both archive and export behavior, while callers need no Developer Portal naming convention.
- Automatic Debug and explicit unsigned Release paths do not require the dynamic values.
- No existing workflow trigger, force branch, build-number calculation, upload/distribution step, tag mutation, public product interface, or persisted schema changes.
- Replacement publication does not weaken the required review check: after #442 merges, a fresh eligible `pull_request_target` event must produce a real schema-valid, passing `codex-review-target` result for the replacement head.
- No constitution change, domain terminology change, or durable architecture reversal is introduced; no ADR or `CONTEXT.md` update is required.

## Project Structure

### Documentation (this feature)

```text
specs/026-testflight-profile-reuse/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/
│   └── requirements.md
├── contracts/
│   └── testflight-profile-handoff.md
└── tasks.md
```

### Source Code (repository root)

```text
project.yml
VitalStride.xcodeproj/project.pbxproj
fastlane/Fastfile
.github/workflows/testflight.yml
scripts/tests/test_testflight_freshness.py
```

**Structure Decision**: `project.yml` owns both the support-resource baseline exclusion and the target-specific signing interface, with `VitalStride.xcodeproj/project.pbxproj` committed only as generated synchronization. T001 keeps those AppUI changes in one layer-scoped commit. The Fastfile and existing TestFlight test module remain RepoInfra and are delivered by T002 in a separate commit. No new workflow, check identity, gate, or test runner is added; `testflight.yml` changes are comment-only signing-description corrections.

## Files in Scope

### AppUI task

- `project.yml` — add the `VitalStride/CONTEXT.md` target-resource exclusion, then apply the two target-specific Release profile substitutions
- `VitalStride.xcodeproj/project.pbxproj` — XcodeGen-produced synchronization only

### RepoInfra task

- `fastlane/Fastfile`
- `scripts/tests/test_testflight_freshness.py`
- `.github/workflows/testflight.yml` — signing comments only; no executable workflow change

## Files NOT to Touch

- `VitalStride/**`, `VitalStrideMac/**`, `VitalStrideWatch Watch App/**`, `VitalStrideWidgets/**`, and all app test roots
- `VitalStride/CONTEXT.md` content and every other `CONTEXT.md`
- `Packages/**` and `Prototype/**`
- Other `.github/workflows/**`, especially `.github/workflows/ci.yml`
- `scripts/test-repoinfra.sh`, other `scripts/**`, hooks, rulesets, review-gate configuration, and security configuration
- Entitlements, bundle identifiers, marketing/build-number settings, telemetry runtime settings, upload/distribution code, release-tag code, and Developer Portal resources
- Credential or local-only paths including `.env*`, `*.p8`, `*.mobileprovision`, keychains, certificates, logs, and build artifacts
- Baseline/roadmap specs, constitution, contexts, and ADRs
- Direct edits to `VitalStride.xcodeproj/**`, PR #441 history, and the MY-1675 / PR #442 implementation

## Interface Contract

### Public signatures

No public Swift, product, package, workflow input, or external API signature changes.

### Internal signing interface

| Target | Canonical fetched-name source | Archive build-setting key | Export bundle mapping |
|---|---|---|---|
| `VitalStride` | `sigh_com.leepepe.vitalstride_appstore_profile-name` | `VITALSTRIDE_APP_PROFILE_SPECIFIER` | `com.leepepe.vitalstride` |
| `VitalStrideWidgets` | `sigh_com.leepepe.vitalstride.widgets_appstore_profile-name` | `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` | `com.leepepe.vitalstride.widgets` |

- `project.yml` Release `PROVISIONING_PROFILE_SPECIFIER` for each target references only its matching interface key.
- The release lane resolves both canonical sources after the forced fetches, rejects missing/empty/equal values before `build_app`, treats each name as opaque shell data for `xcargs`, and uses the same resolved variables in export mapping.
- The action return values are not an alternate name source.
- When signing is explicitly disabled, absent interface values do not block the unsigned Release build.

### AppUI baseline-reconciliation interface

- The `VitalStride` source entry in `project.yml` explicitly excludes `CONTEXT.md` before the two profile substitutions are evaluated.
- The exclusion is the third authorized AppUI truth-source edit and removes only support-document file/resource membership from the generated project; it does not edit or delete the document.
- The generated project is synchronized through XcodeGen and is idempotent when regenerated with the same recorded executable. Direct generated-file edits are forbidden.

## Dependency Strategy

```text
T001 AppUI baseline reconciliation + two-key Release seam
  └─> T002 RepoInfra contract test + lane reuse
        └─> T003 frozen-tree review + replacement publication evidence
              ├─> PR Manager closes #441 with the published replacement link
              └─> MY-1675 / PR #442 exact-head bootstrap merge
                    └─> T004 fresh eligible pull_request_target + real passing codex-review-target
                          └─> PR Manager ships replacement
                                └─> explicit Owner consent
                                      └─> T005 manual TestFlight processing proof
```

- T001 and T002 are separate Fullstack tasks and commits because they own different layers. T001 includes ordered baseline-reconciliation and signing-seam components inside AppUI; T002 depends on the exact two-key contract established by T001.
- T003 is an integration/delivery verification task and changes no source. It freezes the uncommitted tree for exact content review, permits publication only after PASS, and proves the replacement contains clean AppUI then RepoInfra commits. PR #441 remains untouched until replacement publication, after which PR Manager closes it with the replacement link.
- T004 is an external shipping verification edge, not an implementation task or source commit. Replacement preparation may proceed, but shipping is blocked until #442 merges and the replacement obtains its own fresh real review result.
- T005 is a separate production-validation slice, changes no source, and is explicitly blocked until the reviewed delivery is on `main` and the Owner supplies fresh upload consent.
- No task may treat assignment, a static check, or an unsigned build as Owner consent.

## Verification Strategy

Run implementation verification from the repository root.

1. Focused credential-free contract:
   `python3 -B -m unittest scripts.tests.test_testflight_freshness`
2. Fastfile syntax:
   `ruby -c fastlane/Fastfile`
3. Complete RepoInfra gate:
   `bash scripts/test-repoinfra.sh`
4. Confirm `project.yml` excludes `VitalStride/CONTEXT.md`, regenerate the Xcode project, verify the generated file/resource references are absent, and rerun the same recorded XcodeGen executable to prove idempotency:
   `xcodegen generate`
5. Unsigned Release compatibility using a task-local cache:
   `xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/my-1606-derived-data -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
6. Candidate hygiene:
   `git diff --check`

The focused regression must be red-capable: it fails against the historical fixed-name/fallback configuration and passes only when project, archive, and export share the two-key contract. Required PR checks remain `Lint & policy`, `App target`, the six SPM checks, and the required review gate; PR Manager owns their shipping interpretation. For the replacement, review-gate evidence is valid only after #442 has merged into the trusted base and a fresh eligible `pull_request_target` event produces a real schema-valid, passing `codex-review-target` result for the current replacement head.

### Commands forbidden before Owner consent

- `fastlane ios beta`
- Any dispatch of `.github/workflows/testflight.yml`
- Any equivalent ASC upload, Developer Portal mutation, or TestFlight distribution command

### Owner-controlled evidence after consent

The PR description records the manual new-runner procedure but does not execute it. After the reviewed non-Draft `owner-review` PR is merged and fresh Owner consent is recorded, T005 may use the manual workflow on `main`. Evidence is limited to the consent record, run URL, terminal workflow state, and processed TestFlight build identifier; secret values and signing artifacts are excluded.

## Complexity Tracking

No constitutional exception, product dependency, new layer, or ADR is required. MY-1675 / PR #442 is an explicit external shipping dependency, not a code or package dependency.
