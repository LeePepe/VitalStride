# Implementation Plan: TestFlight in-run profile reuse

**Branch**: `026-testflight-profile-reuse` | **Date**: 2026-10-13 | **Spec**: `specs/026-testflight-profile-reuse/spec.md`

**Input**: Feature specification from `specs/026-testflight-profile-reuse/spec.md`

## Summary

Within the AppUI task that owns `project.yml`, first capture the stale tracked project's semantic XcodeGen membership reconciliation as an ordered generated-evidence component, then replace the two fixed Release profile display names with a small two-value signing interface. The generated project remains an unschedulable exclusion and is never hand-edited. The release lane resolves the two canonical profile-name outputs produced by the forced fetches, fails closed if either is unusable, shell-escapes them for archive, and reuses the same values for export. Extend the existing TestFlight freshness test so the `Lint & policy` PR gate rejects archive/export drift without credentials or external mutation, then freeze the local candidate for exact content review before any publication.

## Technical Context

**Language/Version**: Ruby/Fastlane on the self-hosted macOS release runner; YAML/XcodeGen; Python 3 standard-library `unittest`

**Primary Dependencies**: Fastlane actions already used by `fastlane/Fastfile`, Ruby `Shellwords`, XcodeGen, Xcode build settings, GitHub Actions

**Storage**: No product persistence; profile names exist only for the release process lifetime

**Testing**: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; XcodeGen regeneration; unsigned generic-iOS Release build; required PR checks

**Target Platform**: Pull-request CI on `macos-26` and the manual `vitalstride-mac` TestFlight runner

**Project Type**: Cross-layer app build configuration plus repository release automation

**Performance Goals**: No extra ASC fetch, archive, or workflow job; static regression remains within the existing fast RepoInfra gate

**Constraints**: Preserve both `force: true` fetches, target distinction, manual Release/Automatic Debug signing, unsigned builds, all workflow freshness/upload behavior, and secret non-disclosure; do not perform a real upload without explicit Owner consent

**Scale/Scope**: One semantic generated-project baseline component inside T001, two bundle identifiers, two dynamic build-setting keys, one release lane, one existing static-test module, one same-installed-generator idempotency check, and one prepublication freeze/review gate

## Evidence Baseline

- Product/source base: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- Prior planning revision `b26401eb2aabd0c41e412ffb904b270e67109650` is a planning-only child of that product base. The new exact reviewed planning revision published for this repair is the immutable implementation checkout base; its non-planning product tree remains byte-identical to `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- `fastlane/Fastfile` already fetches and installs the app and widget profiles separately with `force: true`.
- Export mapping already consults `sigh_com.leepepe.vitalstride_appstore_profile-name` and `sigh_com.leepepe.vitalstride.widgets_appstore_profile-name`, but falls back to action return values.
- `project.yml` Release configuration contains the two fixed display names that currently control archive selection.
- `scripts/tests/test_testflight_freshness.py` already locks the manual workflow, force/new-commit gate, `main` checkout, and non-cancelling release behavior.
- `scripts/test-repoinfra.sh` auto-discovers `scripts/tests/test_*.py`, and `.github/workflows/ci.yml` invokes it from the PR-required `Lint & policy` job.
- The tracked `project.pbxproj` at the product base is stale. The semantic baseline is observed as 100 additions/4 deletions with the existing WatchTests/Widgets target-reference order or 101/5 when those unchanged references normalize. T001's two Release-setting substitutions are exactly 2/2, so the assembled diagnostic numstat is 102/6 or 103/7. Semantic manifest equality, not numstat or target-list order, is authoritative.
- CI installs XcodeGen without a version pin. Two-run blob equality therefore proves idempotency only for the recorded same installed executable; it does not impose cross-version ordering/blob identity.
- No usable synchronized exact base exists. `84a153962b50f10cd2f49717c4443fb6e953d4ce` carries the same historical membership result but is a divergent 93-file tree; `5b81d9c9d5f4acb5b8b0d2a31b1e6158b91f7cf1` is the unreviewed implementation candidate and is not a base.
- Accepted commit `cc3078c64dd2556fa4cdaa38266b80aba1b71029` removed `VitalStride/Sources/WorkoutSetManager.swift`; the implementation remains in `Packages/VitalModels/Sources/VitalModels/Repo/WorkoutSetManager.swift`. The stale generated reference is the cause of the settings-only unsigned-build failure.

## Constitution Check

### Before design

- Constitution Principle IV / Quality Bar E: PASS. Long-lived target signing shape remains in `project.yml`; T001 captures the semantic baseline and regenerates the tracked output, while hand-edited settings-only output is forbidden.
- Constitution Principle III and ADR-0018/0019: PASS. `project.yml` is the only schedulable AppUI path; `VitalStride.xcodeproj/**` remains a generated exclusion used only as required evidence/output. Fastlane, workflow comments, and regression tests are RepoInfra-owned.
- Quality Bars A and I: PASS. Exact paths and exclusions are declared below, and the defect receives PR-time deterministic regression coverage.
- Quality Bar J: PASS. Required CI state belongs to PR Manager; the content plan does not make AI Reviewer responsible for CI supervision.
- Constitution Development Workflow / ADR-0021: PASS. Planner publishes an exact planning revision and no implementation starts before planning approval. For this Owner-approved VitalStride scope, the workspace prepublication override additionally requires a frozen uncommitted implementation candidate, exact AI Reviewer content `PASS`, and explicit publication permission before commit/push/PR; ADR-0021 resumes for post-publication PR Manager ownership.
- Secret/privacy posture: PASS. Tests consume source text and representative non-secret names only; no credentials, profile contents, certificates, or HealthKit values are introduced.

### After design

- The dependency graph is acyclic: AppUI establishes the two-key interface; RepoInfra consumes it; credential-free integration verification depends on both; Owner-controlled production validation depends on reviewed delivery plus explicit consent.
- The interface is deep and local: two target-specific values determine both archive and export behavior, while callers need no Developer Portal naming convention.
- Automatic Debug and explicit unsigned Release paths do not require the dynamic values.
- No existing workflow trigger, force branch, build-number calculation, upload/distribution step, tag mutation, public product interface, or persisted schema changes.
- Existing source/test content does not change. T001's semantic generated baseline component adds only the current memberships in the handoff contract, removes only the stale app-target `WorkoutSetManager.swift` reference, permits only the declared target-reference ordering variant, and preserves the package implementation.
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

### Required generated evidence

- `VitalStride.xcodeproj/project.pbxproj` — regenerated and committed under Constitution IV to show the semantic baseline plus the two target-specific Release-setting substitutions; generated exclusion, not a separately schedulable/owned path; no handwritten edit

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
- The accepted source/test files named by the generated membership manifest; they are read-only inputs and MUST NOT be edited, deleted, or restored by this feature

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

### Generated-project baseline contract

- The exact reviewed planning revision is the immutable implementation checkout base; its product/source tree is `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- Before evaluating the two profile-setting substitutions, T001's generated evidence must match the semantic membership/resource/removal manifest in `contracts/testflight-profile-handoff.md` and include no source/test edit.
- The stale app-target `WorkoutSetManager.swift` reference is removed; the package implementation remains untouched.
- The unchanged WatchTests/Widgets target-reference order may remain or normalize; no membership changes with it. Baseline 100/4 versus 101/5 and assembled 102/6 versus 103/7 are diagnostic variants, not acceptance.
- After the semantic baseline is established, the profile-setting portion of `project.pbxproj` is exactly the two target-specific 2/2 substitutions. A second generation with the recorded same XcodeGen executable produces the same blob.

## Dependency Strategy

```text
T001 AppUI truth-source edit + ordered generated evidence
  └─> T002 RepoInfra contract test + lane reuse
        └─> T003-A freeze uncommitted candidate + credential-free evidence
              └─> exact AI Reviewer PASS + publication permission
                    └─> T003-B commit/push/non-Draft PR + identity proof
                          └─> PR Manager required checks + merge
                                └─> explicit Owner consent
                                      └─> T004 manual TestFlight processing proof
```

- T001 is AppUI-owned because `project.yml` is its only schedulable/writable layer path. Its baseline and setting portions are separately reviewable generated-evidence components without scheduling the generated exclusion or treating the current unreviewed implementation commit as a base.
- T002 is a separate RepoInfra task and depends on the exact two-key contract established by T001.
- T003 is an integration/delivery verification task and changes no source. Stage A freezes the uncommitted tree and proves the assembled contract without Apple access; Stage B is blocked until exact content `PASS` and publication permission for that tree, then publishes it and proves reviewed-tree/local/remote/PR identity before PR Manager handoff.
- T004 is a separate production-validation slice, changes no source, and is explicitly blocked until the reviewed delivery is on `main` and the Owner supplies fresh upload consent.
- No task may treat assignment, a static check, or an unsigned build as Owner consent.

## Verification Strategy

Run implementation verification from the repository root.

1. Confirm the checkout is the exact reviewed planning revision and record that its product tree is `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
2. Record `xcodegen --version`; establish and inspect T001's semantic baseline component, compare `VitalStride.xcodeproj/project.pbxproj` against the handoff manifest and permitted WatchTests/Widgets ordering variant, confirm no source/test path changes, and run `git diff --check`.
3. Verify T001's assembled output contributes only the two app/widget setting substitutions beyond that baseline; record the project blob, rerun the same XcodeGen executable, and require the blob to remain equal.
4. Focused credential-free contract:
   `python3 -B -m unittest scripts.tests.test_testflight_freshness`
5. Fastfile syntax:
   `ruby -c fastlane/Fastfile`
6. Complete RepoInfra gate:
   `bash scripts/test-repoinfra.sh`
7. Unsigned Release compatibility using a task-local cache:
   `xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/my-1606-derived-data -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
8. Candidate hygiene:
   `git diff --check`

The focused regression must be red-capable: it fails against the historical fixed-name/fallback configuration and passes only when project, archive, and export share the two-key contract. Before publication, T003 freezes this local evidence and obtains exact AI Reviewer content `PASS` plus explicit permission. Only then may Fullstack commit/push/create-or-update the non-Draft `owner-review` PR and prove the reviewed tree matches local HEAD, remote branch OID, and PR `headRefOid`. Required checks remain `Lint & policy`, `App target`, the six SPM checks, and the required review gate; PR Manager owns their post-publication shipping interpretation.

### Commands forbidden before Owner consent

- `fastlane ios beta`
- Any dispatch of `.github/workflows/testflight.yml`
- Any equivalent ASC upload, Developer Portal mutation, or TestFlight distribution command

### Owner-controlled evidence after consent

After publication permission, the PR description records the manual new-runner procedure but does not execute it. After the non-Draft `owner-review` PR is merged by PR Manager and fresh Owner consent is recorded, T004 may use the manual workflow on `main`. Evidence is limited to the consent record, run URL, terminal workflow state, and processed TestFlight build identifier; secret values and signing artifacts are excluded.

## Complexity Tracking

No constitutional exception, new dependency, new layer, or ADR is required. The baseline is an ordered evidence component inside T001, not a generated-output owner layer or independently schedulable task. The scoped workspace override controls prepublication ordering for this VitalStride delivery.
