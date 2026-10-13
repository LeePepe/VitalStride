---

description: "Layer-scoped task graph for TestFlight in-run profile reuse"

---

# Tasks: TestFlight in-run profile reuse

**Input**: Design documents from `specs/026-testflight-profile-reuse/`

**Prerequisites**: `spec.md`, `plan.md`, `research.md`, `data-model.md`, `contracts/testflight-profile-handoff.md`, `quickstart.md`, `checklists/requirements.md`

**Organization**: US1 delivers the two-layer archive/export profile handoff. US2 adds credential-free delivery evidence and a separately blocked Owner-controlled production validation.

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
| Files in scope | `project.yml`, the sole schedulable/writable AppUI truth-source path |
| Required generated artifact | `VitalStride.xcodeproj/project.pbxproj` is regenerated and committed as Constitution IV evidence/output only. It remains an unschedulable generated exclusion and MUST NOT be hand-edited or assigned separate layer ownership. |
| Files out of scope | Direct edits to `VitalStride.xcodeproj/**`; all app/source/test roots; `Packages/**`; `Prototype/**`; `.github/**`; `fastlane/**`; `scripts/**`; entitlements; bundle IDs; unrelated target/build settings |
| Interface impact | Internal-only: app Release `PROVISIONING_PROFILE_SPECIFIER` consumes `VITALSTRIDE_APP_PROFILE_SPECIFIER`; widget Release consumes `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER`. No public product signature. |
| Task-local acceptance | Ordered component A records the installed XcodeGen version and, before the truth-source edit is evaluated, proves the generated output matches the handoff contract's semantic membership/resource/removal manifest with no source/test edit. The only permitted structural variant is the unchanged WatchTests/Widgets target-reference order; baseline 100/4 or 101/5 numstat is diagnostic only. Component B changes only the two `project.yml` Release profile specifiers, regenerates the artifact, and contributes exactly 2 additions/2 deletions beyond the semantic baseline, yielding diagnostic assembled 102/6 or 103/7. Fixed names are absent; target keys are not crossed; Release remains Manual + Apple Distribution; base/Debug remains Automatic; signing-disabled Release requires neither value; a second generation with the recorded same executable produces the same project blob. No commit split or history rewrite is required to present the two components separately in review. |
| Verification | From repo root, follow `quickstart.md`: record `xcodegen --version`; compare the generated diff with the semantic manifest and permitted ordering variant; run `xcodegen generate`, `git diff --check`, record `git hash-object VitalStride.xcodeproj/project.pbxproj`, rerun the same executable, and require the blob hash to remain equal; then run the unsigned Release command. |
| Blocking edges | None. Establishes the exact interface consumed by T002. |

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

**Goal**: A frozen local candidate receives exact content review and explicit publication permission before the unchanged tree becomes a non-Draft PR; real TestFlight validation stays visibly blocked until Owner consent.

**Independent Test**: Freeze the uncommitted local tree and credential-free evidence, obtain exact AI Reviewer `PASS` plus publication permission, then prove the committed/pushed/PR tree is identical to the reviewed tree and that no production workflow was dispatched.

- [ ] T003 [US2] Assemble credential-free delivery evidence for `project.yml`, `VitalStride.xcodeproj/project.pbxproj`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`, and `.github/workflows/testflight.yml`

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer | Cross-layer integration/delivery verification; no change-owner path |
| Context | `RepoInfra/CONTEXT.md`; `VitalStride/CONTEXT.md`; Constitution Development Workflow and Quality Bar J; Owner-approved VitalStride scoped prepublication contract |
| Vertical slice | `US2` credential-free freeze/review/publication proof |
| Files in scope | Verification-only access to `project.yml`, `VitalStride.xcodeproj/project.pbxproj`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`, `.github/workflows/testflight.yml`; frozen-tree manifest; after publication permission only, Git branch/commit and PR metadata/evidence |
| Files out of scope | Source repair inside T003; commit, push, or PR creation/update before permission; Developer Portal; ASC release operations; credentials; profile/certificate/keychain contents; real workflow dispatch |
| Interface impact | None. Verifies the assembled internal contract and delivery constraints. |
| Task-local acceptance | **Stage A — prepublication:** T001/T002 verification is fresh; the semantic generated manifest and two setting substitutions are separately evidenced; static regression is auto-discovered by the existing PR policy path; the uncommitted local tree, manifest, and credential-free results are frozen; no commit, push, or PR creation/update has occurred. Exact AI Reviewer content `PASS` for that frozen tree and explicit publication permission are mandatory; any content change invalidates permission and returns to Stage A. **Stage B — post-PASS only:** Fullstack commits and pushes the unchanged reviewed tree, creates or updates a non-Draft `owner-review` PR, proves reviewed tree = commit tree and local SHA = remote branch OID = PR `headRefOid`, records the required PR description, and hands the published mapping to PR Manager. No real TestFlight run is claimed or triggered. |
| Verification | Stage A, from repo root: rerun `quickstart.md` through the unsigned Release section; run `git diff --check`; inspect `.github/workflows/ci.yml` read-only for the unchanged `Lint & policy` → `bash scripts/test-repoinfra.sh` path; record frozen-tree manifest/hash and the exact AI Reviewer verdict/permission. Stage B manual evidence: non-Draft PR URL, `owner-review` label, PR validation text, tree equality, local/remote/PR SHA equality, verified PR Manager handoff run, and no TestFlight run URL before consent. |
| Blocking edges | Depends on T001 and T002. Stage A blocks exact content review; PASS plus publication permission blocks Stage B; Stage B blocks PR Manager required-check supervision/merge. T004 remains separately blocked. |

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
T001 AppUI truth-source edit + ordered generated evidence
  └─> T002 RepoInfra lane + regression
        └─> T003-A freeze uncommitted candidate + local evidence
              └─> exact AI Reviewer PASS + publication permission
                    └─> T003-B commit/push/non-Draft PR + identity proof
                          └─> PR Manager required checks + merge
                                └─> explicit Owner consent
                                      └─> T004 manual processed-build proof
```

- T001 is the only AppUI task. It owns `project.yml`; baseline reconciliation and setting synchronization are ordered generated-evidence components, not separate tasks or layer ownership for `VitalStride.xcodeproj/**`.
- No implementation task spans AppUI and RepoInfra ownership.
- T003 is verification/delivery-only and may not repair either owning layer; a generated-membership or Release-setting failure routes to T001, and a RepoInfra failure routes to T002. PR check results after publication belong to PR Manager.
- T003-A forbids publication. T003-B is unreachable without exact content `PASS` and explicit publication permission for the same frozen tree.
- T004 is not normal implementation verification and cannot be scheduled before its external consent edge is satisfied.
- Team Lead reconciles and dispatches the reviewed graph; Planner Lead and AI Reviewer do not assign implementation roles.

## Acceptance Traceability

| Spec acceptance | Slice | Tasks | Verification surface |
|---|---|---|---|
| US1/AC5; FR-013; RB-004; SC-006 | US1 | T001 | Semantic generated manifest, stale-reference removal, permitted ordering variants, same-executable idempotency, unsigned Release build |
| US1/AC1; FR-001, FR-003, FR-004; RB-001 | US1 | T001, T002 | Static target/source mapping, fixed-name removal, and generated project |
| US1/AC2; FR-002; RB-002 | US1 | T002 | Missing/empty/equal source regression, fallback removal, and pre-archive failure contract |
| US1/AC3; FR-005 | US1 | T002 | Shell-safe opaque transport assertions |
| US1/AC4; FR-006, FR-007 | US1 | T001, T003 | XcodeGen sync and unsigned generic-iOS Release build |
| US2/AC1, US2/AC2; FR-008; RB-003 | US2 | T002, T003 | Focused unittest, preserved existing assertions, and `bash scripts/test-repoinfra.sh` on the existing PR path |
| US2/AC3; FR-009, FR-011; RB-005 | US2 | T002, T003 | Frozen-tree review/permission before unchanged-tree publication; non-Draft PR, label, description, identity proof, PR Manager handoff |
| US2/AC4; FR-010 | US2 | T003, T004 | Absence of pre-consent dispatch; explicit blocked edge |
| US2/AC5; FR-012 | US2 | T004 | Consent record, run URL/head, terminal success, processed build identifier |
| SC-001, SC-002 | US1/US2 | T002, T003 | Focused and full RepoInfra results |
| SC-003 | US1 | T001, T003 | XcodeGen synchronization and unsigned Release result |
| SC-004 | US2 | T003 | PR Manager-owned required-check evidence |
| SC-005 | US2 | T004 | Owner-consented production evidence |

## Implementation Strategy

1. T001 establishes the semantic baseline and two-key AppUI interface as ordered generated-evidence components while owning only `project.yml`.
2. T002 writes the contract regression first, observes the historical signing state fail it, then repairs only RepoInfra until focused and complete gates pass.
3. T003-A freezes the uncommitted candidate and local evidence; exact AI Reviewer content `PASS` plus publication permission is required for that tree.
4. T003-B publishes only the unchanged reviewed tree, proves local/remote/PR identity, and hands the PR mapping to PR Manager.
5. PR Manager supervises required checks and merge; T004 remains blocked unless and until the Owner explicitly authorizes the real upload.
