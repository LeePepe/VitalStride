# Implementation Plan: TestFlight in-run profile reuse

**Branch**: `026-testflight-profile-reuse` | **Date**: 2026-10-13 | **Spec**: `specs/026-testflight-profile-reuse/spec.md`

**Input**: Feature specification from `specs/026-testflight-profile-reuse/spec.md`

## Summary

Replace the two fixed Release profile display names with a small two-value signing interface. `project.yml` gives the app and widget distinct dynamic inputs; the release lane resolves the two canonical profile-name outputs produced by the forced fetches, fails closed if either is unusable, shell-escapes them for archive, and reuses the same values for export. Extend the existing TestFlight freshness test so the `Lint & policy` PR gate rejects any archive/export drift without credentials, signing, Developer Portal access, or upload.

## Technical Context

**Language/Version**: Ruby/Fastlane on the self-hosted macOS release runner; YAML/XcodeGen; Python 3 standard-library `unittest`

**Primary Dependencies**: Fastlane actions already used by `fastlane/Fastfile`, Ruby `Shellwords`, XcodeGen, Xcode build settings, GitHub Actions

**Storage**: No product persistence; profile names exist only for the release process lifetime

**Testing**: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; XcodeGen regeneration; unsigned generic-iOS Release build; required PR checks

**Target Platform**: Pull-request CI on `macos-26` and the manual `vitalstride-mac` TestFlight runner

**Project Type**: Cross-layer app build configuration plus repository release automation

**Performance Goals**: No extra ASC fetch, archive, or workflow job; static regression remains within the existing fast RepoInfra gate

**Constraints**: Preserve both `force: true` fetches, target distinction, manual Release/Automatic Debug signing, unsigned builds, all workflow freshness/upload behavior, and secret non-disclosure; do not perform a real upload without explicit Owner consent

**Scale/Scope**: Two bundle identifiers, two dynamic build-setting keys, one release lane, one existing static-test module, one generated project sync

## Evidence Baseline

- Base revision: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- `fastlane/Fastfile` already fetches and installs the app and widget profiles separately with `force: true`.
- Export mapping already consults `sigh_com.leepepe.vitalstride_appstore_profile-name` and `sigh_com.leepepe.vitalstride.widgets_appstore_profile-name`, but falls back to action return values.
- `project.yml` Release configuration contains the two fixed display names that currently control archive selection.
- `scripts/tests/test_testflight_freshness.py` already locks the manual workflow, force/new-commit gate, `main` checkout, and non-cancelling release behavior.
- `scripts/test-repoinfra.sh` auto-discovers `scripts/tests/test_*.py`, and `.github/workflows/ci.yml` invokes it from the PR-required `Lint & policy` job.

## Constitution Check

### Before design

- Constitution Principle IV / Quality Bar E: PASS. Long-lived target signing shape remains in `project.yml`; the tracked Xcode project is regenerated only as synchronized output.
- Constitution Principle III and ADR-0018/0019: PASS. App target configuration is AppUI-owned; Fastlane, workflow comments, and regression tests are RepoInfra-owned, so implementation is split by layer.
- Quality Bars A and I: PASS. Exact paths and exclusions are declared below, and the defect receives PR-time deterministic regression coverage.
- Quality Bar J: PASS. Required CI state belongs to PR Manager; the content plan does not make AI Reviewer responsible for CI supervision.
- Constitution Development Workflow / ADR-0021: PASS. Planner publishes an exact planning revision; no implementation starts before AI Reviewer and Team Lead approval.
- Secret/privacy posture: PASS. Tests consume source text and representative non-secret names only; no credentials, profile contents, certificates, or HealthKit values are introduced.

### After design

- The dependency graph is acyclic: AppUI establishes the two-key interface; RepoInfra consumes it; credential-free integration verification depends on both; Owner-controlled production validation depends on reviewed delivery plus explicit consent.
- The interface is deep and local: two target-specific values determine both archive and export behavior, while callers need no Developer Portal naming convention.
- Automatic Debug and explicit unsigned Release paths do not require the dynamic values.
- No existing workflow trigger, force branch, build-number calculation, upload/distribution step, tag mutation, public product interface, or persisted schema changes.
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

**Structure Decision**: `project.yml` owns the target-specific interface, with `VitalStride.xcodeproj/project.pbxproj` committed only as generated synchronization. The Fastfile owns resolution and reuse of the in-run values. The existing TestFlight test module owns static contract coverage and is already wired into PR CI, so no new workflow, gate, or test runner is added. `testflight.yml` changes are comment-only corrections to the signing description.

## Files in Scope

### AppUI task

- `project.yml`
- `VitalStride.xcodeproj/project.pbxproj` — XcodeGen-produced synchronization only

### RepoInfra task

- `fastlane/Fastfile`
- `scripts/tests/test_testflight_freshness.py`
- `.github/workflows/testflight.yml` — signing comments only; no executable workflow change

## Files NOT to Touch

- `VitalStride/**`, `VitalStrideMac/**`, `VitalStrideWatch Watch App/**`, `VitalStrideWidgets/**`, and all app test roots
- `Packages/**` and `Prototype/**`
- Other `.github/workflows/**`, especially `.github/workflows/ci.yml`
- `scripts/test-repoinfra.sh`, other `scripts/**`, hooks, rulesets, review-gate configuration, and security configuration
- Entitlements, bundle identifiers, marketing/build-number settings, telemetry runtime settings, upload/distribution code, release-tag code, and Developer Portal resources
- Credential or local-only paths including `.env*`, `*.p8`, `*.mobileprovision`, keychains, certificates, logs, and build artifacts
- Baseline/roadmap specs, constitution, contexts, and ADRs

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

## Dependency Strategy

```text
T001 AppUI two-key Release seam
  └─> T002 RepoInfra contract test + lane reuse
        └─> T003 credential-free integration evidence
              └─> reviewed non-Draft PR merged to main
                    └─> explicit Owner consent
                          └─> T004 manual TestFlight processing proof
```

- T001 and T002 are separate Fullstack tasks because they own different layers. T002 depends on the exact two-key contract established by T001.
- T003 is an integration/test-layer verification task and changes no source. It proves the assembled contract without Apple access.
- T004 is a separate production-validation slice, changes no source, and is explicitly blocked until the reviewed delivery is on `main` and the Owner supplies fresh upload consent.
- No task may treat assignment, a static check, or an unsigned build as Owner consent.

## Verification Strategy

Run implementation verification from the repository root.

1. Focused credential-free contract:
   `python3 -B -m unittest scripts.tests.test_testflight_freshness`
2. Fastfile syntax:
   `ruby -c fastlane/Fastfile`
3. Complete RepoInfra gate:
   `bash scripts/test-repoinfra.sh`
4. Regenerate the Xcode project:
   `xcodegen generate`
5. Unsigned Release compatibility using a task-local cache:
   `xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/my-1606-derived-data -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
6. Candidate hygiene:
   `git diff --check`

The focused regression must be red-capable: it fails against the historical fixed-name/fallback configuration and passes only when project, archive, and export share the two-key contract. Required PR checks remain `Lint & policy`, `App target`, the six SPM checks, and the required review gate; PR Manager owns their shipping interpretation.

### Commands forbidden before Owner consent

- `fastlane ios beta`
- Any dispatch of `.github/workflows/testflight.yml`
- Any equivalent ASC upload, Developer Portal mutation, or TestFlight distribution command

### Owner-controlled evidence after consent

The PR description records the manual new-runner procedure but does not execute it. After the reviewed non-Draft `owner-review` PR is merged and fresh Owner consent is recorded, T004 may use the manual workflow on `main`. Evidence is limited to the consent record, run URL, terminal workflow state, and processed TestFlight build identifier; secret values and signing artifacts are excluded.

## Complexity Tracking

No constitutional exception, new dependency, new layer, or ADR is required.
