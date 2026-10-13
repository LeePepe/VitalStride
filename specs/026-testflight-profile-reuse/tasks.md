---

description: "Layer-scoped task graph for TestFlight in-run profile reuse"

---

# Tasks: TestFlight in-run profile reuse

**Input**: Design documents from `specs/026-testflight-profile-reuse/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/testflight-profile-handoff.md`, `quickstart.md`, `checklists/requirements.md`

**Organization**: US1 delivers the two-layer archive/export profile handoff. US2 adds credential-free delivery evidence and a separately blocked Owner-controlled production validation.

## Phase 0: User Story 1 prerequisite - Reconcile the generated AppUI baseline

**Goal**: Make the tracked Xcode project a deterministic realization of the existing `project.yml` and accepted source tree before evaluating the two profile-setting changes.

**Independent Test**: From the exact reviewed planning checkout, regenerate twice, prove the project hash is stable, match the exact membership manifest, confirm no source/config content changed, and complete an unsigned generic-iOS Release build.

- [ ] T000 [US1] Reconcile the audited generated membership baseline only in `VitalStride.xcodeproj/project.pbxproj`

### T000 metadata

| Field | Contract |
|---|---|
| Owning layer | `AppUI` generated-synchronization boundary |
| Context | `VitalStride/CONTEXT.md`; Constitution Principle IV; ADR-0018/0019 generated-output classification |
| Vertical slice | `US1` prerequisite |
| Files in scope | `VitalStride.xcodeproj/project.pbxproj` only, as deterministic XcodeGen output from the exact reviewed planning checkout |
| Files out of scope | `project.yml`; every app/package source; every test/context file; `.github/**`; `fastlane/**`; `scripts/**`; all other repository paths |
| Interface impact | None. Reconciles generated memberships already declared by the source-of-truth configuration; adds no product/public contract. |
| Task-local acceptance | The generated component is exactly 101 additions/5 deletions and matches `contracts/testflight-profile-handoff.md`: 20 existing source/test memberships, four Mac shared memberships, one existing context resource, structural WatchTests ordering only, and removal only of the stale app-target `VitalStride/Sources/WorkoutSetManager.swift` reference. The package implementation remains. No source/config content changes. Two consecutive generations produce the same project hash. |
| Verification | From repo root on the exact reviewed planning checkout: `xcodegen generate`; inspect `git diff --unified=0 -- VitalStride.xcodeproj/project.pbxproj` against the contract manifest; `git diff --check`; record `git hash-object VitalStride.xcodeproj/project.pbxproj`, run `xcodegen generate` again, and require the hash to remain equal; run the unsigned Release command in `quickstart.md`. |
| Blocking edges | None. Blocks T001; T001's setting portion cannot be evaluated against the stale project. |

**Checkpoint**: The full membership drift is authorized and independently evidenced. This task does not authorize the current implementation SHA, require a history rewrite, or permit source edits; an assembled candidate may present T000 and T001 as distinct diff components for one exact-revision review.

## Phase 1: User Story 1 - Archive with the profiles fetched in this run (Priority: P1)

**Goal**: App and widget signed archive/export consume their own canonical profile names fetched in the same run, while unsigned Release builds remain credential-free.

**Independent Test**: Generate the project, run the static profile-handoff regression, and complete an unsigned generic-iOS Release build without Apple access.

- [ ] T001 [US1] Replace the two fixed Release profile names with the target-specific signing interface in `project.yml` and regenerate `VitalStride.xcodeproj/project.pbxproj`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `AppUI` |
| Context | `VitalStride/CONTEXT.md`; Constitution Principle IV |
| Vertical slice | `US1` |
| Files in scope | `project.yml`; the two corresponding generated Release-setting substitutions in `VitalStride.xcodeproj/project.pbxproj` after T000 |
| Files out of scope | All app/source/test roots; `Packages/**`; `Prototype/**`; `.github/**`; `fastlane/**`; `scripts/**`; entitlements; bundle IDs; unrelated target/build settings |
| Interface impact | Internal-only: app Release `PROVISIONING_PROFILE_SPECIFIER` consumes `VITALSTRIDE_APP_PROFILE_SPECIFIER`; widget Release consumes `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER`. No public product signature. |
| Task-local acceptance | Fixed profile display names are absent; the two keys are not crossed; Release remains Manual + Apple Distribution; base/Debug remains Automatic; signing-disabled Release does not require either value; relative to T000's synchronized project, the generated setting component contains only the two corresponding profile substitutions. The complete base-to-candidate project delta is the authorized T000 101/5 component plus this T001 2/2 component. |
| Verification | From repo root: `xcodegen generate`; `xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/my-1606-derived-data -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`; `git diff --check` |
| Blocking edges | Depends on T000. Establishes the exact interface consumed by T002. |

- [ ] T002 [US1] Add red-capable profile-handoff regression coverage and make the release lane reuse the validated in-run names in `scripts/tests/test_testflight_freshness.py`, `fastlane/Fastfile`, and signing comments in `.github/workflows/testflight.yml`

### T002 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` |
| Context | `RepoInfra/CONTEXT.md`; Constitution Quality Bars A and I |
| Vertical slice | `US1` |
| Files in scope | `scripts/tests/test_testflight_freshness.py`; `fastlane/Fastfile`; comment-only signing-description corrections in `.github/workflows/testflight.yml` |
| Files out of scope | `project.yml` and generated project; other workflows; `scripts/test-repoinfra.sh`; other scripts/tests; product/app/package paths; secrets/security config; upload/distribution/tag behavior |
| Interface impact | Consumes the two T001 keys. Resolves the existing canonical app/widget profile-name sources once, validates them, shell-safely transports them to archive, and reuses the same variables in export. Removes the action-return fallback. No workflow input or public product signature change. |
| Task-local acceptance | Add tests before production edits and demonstrate that the historical fixed-name/fallback state violates them; preserve the existing four freshness cases; both forced installed fetches remain; missing/empty/equal values fail before `build_app`; names are shell-safe and target-correct; export reuses archive variables; no fixed name, fallback, global profile override, credential read, signing, upload, or external mutation occurs in tests. |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; `git diff --check` |
| Blocking edges | Depends on T001's exact two-key interface. Blocks T003. |

**Checkpoint**: US1 is independently demonstrable without ASC access: the contract test is green, XcodeGen is synchronized, Fastfile syntax is valid, and the unsigned Release build succeeds.

## Phase 2: User Story 2 - Detect signing drift before release (Priority: P1)

**Goal**: A non-Draft reviewed candidate carries complete credential-free proof, while real TestFlight validation stays visibly blocked until Owner consent.

**Independent Test**: Run the focused and complete local gates, confirm PR-time wiring and candidate constraints, and verify that no production workflow was dispatched.

- [ ] T003 [US2] Assemble credential-free delivery evidence for `project.yml`, `VitalStride.xcodeproj/project.pbxproj`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`, and `.github/workflows/testflight.yml`

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` integration/test surface |
| Context | `RepoInfra/CONTEXT.md`; `VitalStride/CONTEXT.md`; Constitution Development Workflow and Quality Bar J |
| Vertical slice | `US2` credential-free PR proof |
| Files in scope | Verification-only access to `project.yml`, `VitalStride.xcodeproj/project.pbxproj`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`, `.github/workflows/testflight.yml`, and existing PR check results; no source edits |
| Files out of scope | All repository mutation; Developer Portal; ASC release operations; credentials; profile/certificate/keychain contents; real workflow dispatch |
| Interface impact | None. Verifies the assembled internal contract and delivery constraints. |
| Task-local acceptance | T000, T001, and T002 verification is fresh; static regression is auto-discovered by the existing PR policy gate; generated membership and settings match their distinct authorized components and a second generation is clean; PR is non-Draft with `owner-review`; PR description contains the new-runner procedure and consent prerequisite; required checks are handed to PR Manager; no real TestFlight run is claimed or triggered. |
| Verification | From repo root, rerun all commands in `specs/026-testflight-profile-reuse/quickstart.md` through the unsigned Release section; run `git diff --check`; inspect `.github/workflows/ci.yml` read-only to confirm the unchanged `Lint & policy` → `bash scripts/test-repoinfra.sh` PR path. Manual evidence: non-Draft PR URL, `owner-review` label, PR validation text, and no TestFlight run URL before consent. |
| Blocking edges | Depends on T000, T001, and T002. Implementation delivery may proceed through normal exact review and required CI after T003; T004 remains separately blocked. |

- [ ] T004 [US2] After reviewed merge and explicit Owner consent, perform and record the single manual production validation through `.github/workflows/testflight.yml`

### T004 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` production-validation surface |
| Context | `RepoInfra/CONTEXT.md`; DEC-026-003 |
| Vertical slice | `US2` Owner-controlled production proof |
| Files in scope | Execution-only use of the existing `.github/workflows/testflight.yml`; no repository edit |
| Files out of scope | Any dispatch before consent; workflow/Fastfile/source changes; Developer Portal cleanup or certificate/profile revocation; secret/profile/certificate/keychain disclosure; automated publication |
| Interface impact | None. Exercises the already reviewed release path on `main`. |
| Task-local acceptance | Gate evidence proves: reviewed implementation merged to `main`; explicit current Owner consent; non-Draft `owner-review` PR history; one manual workflow run using unchanged force semantics; terminal upload success; Apple processing completion; app/widget archive used the two in-run profiles; evidence contains no sensitive values or artifacts. |
| Verification | **Blocked until Owner consent.** Manual evidence form: Owner consent comment/decision ID, GitHub Actions run URL and head SHA on `main`, terminal conclusion, and processed TestFlight build identifier. Do not attach logs containing secrets, `.p8`, `.mobileprovision`, certificates, or keychain output. |
| Blocking edges | Depends on T003, implementation merge through PR Manager, and explicit Owner consent. Without consent it remains explicitly blocked and must not be dispatched. |

**Checkpoint**: US2 credential-free delivery can complete at T003. The issue's production outcome completes only when T004 receives consent and records processed-build evidence.

## Dependencies & Execution Order

```text
T000 AppUI generated baseline reconciliation
  └─> T001 AppUI signing seam
        └─> T002 RepoInfra lane + regression
              └─> T003 credential-free PR evidence
                    └─> exact implementation review + PR Manager merge
                          └─> explicit Owner consent
                                └─> T004 manual processed-build proof
```

- T000 and T001 are serialized AppUI components over the same generated path; T000 authorizes historical membership reconciliation, while T001 owns only the two setting substitutions relative to that state.
- No implementation task spans AppUI and RepoInfra ownership.
- T003 is verification-only and may not repair either owning layer; a generated-membership failure routes to T000, a Release-setting failure routes to T001, and a RepoInfra/CI failure routes to T002.
- T004 is not normal implementation verification and cannot be scheduled before its external consent edge is satisfied.
- Team Lead reconciles and dispatches the reviewed graph; Planner Lead and AI Reviewer do not assign implementation roles.

## Acceptance Traceability

| Spec acceptance | Slice | Tasks | Verification surface |
|---|---|---|---|
| US1/AC5; FR-013; RB-004; SC-006 | US1 | T000 | Exact generated membership manifest, stale-reference removal, two-generation hash equality, unsigned Release build |
| US1/AC1; FR-001, FR-003, FR-004 | US1 | T001, T002 | Static target/source mapping plus generated project |
| US1/AC2; FR-002 | US1 | T002 | Missing/empty/equal source regression and pre-archive failure contract |
| US1/AC3; FR-005 | US1 | T002 | Shell-safe opaque transport assertions |
| US1/AC4; FR-006, FR-007 | US1 | T000, T001, T003 | XcodeGen sync and unsigned generic-iOS Release build |
| US2/AC1, US2/AC2; FR-008 | US2 | T002, T003 | Focused unittest and `bash scripts/test-repoinfra.sh` on the existing PR path |
| US2/AC3; FR-009, FR-011 | US2 | T002, T003 | Preserved freshness tests; non-Draft PR, label, description, required checks |
| US2/AC4; FR-010 | US2 | T003, T004 | Absence of pre-consent dispatch; explicit blocked edge |
| US2/AC5; FR-012 | US2 | T004 | Consent record, run URL/head, terminal success, processed build identifier |
| SC-001, SC-002 | US1/US2 | T002, T003 | Focused and full RepoInfra results |
| SC-003 | US1 | T000, T001, T003 | XcodeGen synchronization and unsigned Release result |
| SC-004 | US2 | T003 | PR Manager-owned required-check evidence |
| SC-005 | US2 | T004 | Owner-consented production evidence |

## Implementation Strategy

1. T000 establishes the exact generated baseline reconciliation from the reviewed checkout and proves idempotent unsigned compatibility without source edits.
2. T001 establishes the explicit AppUI signing interface; its setting component is evaluated relative to T000 even if both components appear in one exact candidate.
3. T002 writes the contract regression first, observes the historical signing state fail it, then repairs only RepoInfra until focused and complete gates pass.
4. T003 assembles fresh local/PR evidence and publishes a non-Draft `owner-review` candidate without triggering TestFlight.
5. Normal exact-candidate review and PR Manager shipping proceed under ADR-0021.
6. T004 remains blocked unless and until the Owner explicitly authorizes the real upload; after consent it records only the approved production evidence.
