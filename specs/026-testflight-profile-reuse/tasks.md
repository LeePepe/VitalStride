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

- [ ] T001 [US1] Reconcile the support-resource baseline and replace the two fixed Release profile names in `project.yml`, then regenerate `VitalStride.xcodeproj/project.pbxproj`

### T001 metadata

| Field | Contract |
|---|---|
| Owning layer | `AppUI` |
| Context | `VitalStride/CONTEXT.md`; Constitution Principle IV |
| Vertical slice | `US1` |
| Files in scope | `project.yml`, the sole schedulable AppUI truth source; generated synchronization evidence only in `VitalStride.xcodeproj/project.pbxproj` |
| Files out of scope | Direct edits to `VitalStride.xcodeproj/**`; `VitalStride/CONTEXT.md` content and every other context; all app/source/test roots; `Packages/**`; `Prototype/**`; `.github/**`; `fastlane/**`; `scripts/**`; entitlements; bundle IDs; unrelated target/build settings |
| Interface impact | Internal-only: baseline reconciliation excludes `VitalStride/CONTEXT.md` from `VitalStride` target resources; app Release `PROVISIONING_PROFILE_SPECIFIER` consumes `VITALSTRIDE_APP_PROFILE_SPECIFIER`; widget Release consumes `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER`. No public product signature. |
| Task-local acceptance | Component A adds the `CONTEXT.md` source exclusion to `project.yml` and proves regenerated file/resource membership omits the unchanged support document. Component B replaces exactly the two fixed profile settings. The resulting same-layer AppUI commit contains only these three truth-source edits plus XcodeGen-produced synchronization. Fixed names are absent; keys are target-correct; Release remains Manual + Apple Distribution; base/Debug remains Automatic; signing-disabled Release requires neither value; the same recorded XcodeGen executable is idempotent; the observed `99/7` generated numstat is diagnostic rather than normative. |
| Verification | From repo root: record `xcodegen --version`; run `xcodegen generate`; verify `VitalStride/CONTEXT.md` file/resource references are absent and only the authorized baseline plus profile substitutions appear; record the generated blob, rerun the same executable, and require the blob to remain unchanged; run `xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride -configuration Release -destination 'generic/platform=iOS' -derivedDataPath .build/my-1606-derived-data -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`; run `git diff --check` |
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
| Task-local acceptance | In a separate RepoInfra commit after T001, add tests before production edits and demonstrate that the historical fixed-name/fallback state violates them; preserve the existing four freshness cases; both forced installed fetches remain; missing/empty/equal values fail before `build_app`; names are shell-safe and target-correct; export reuses archive variables; no fixed name, fallback, global profile override, credential read, signing, upload, or external mutation occurs in tests. |
| Verification | From repo root: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; `git diff --check` |
| Blocking edges | Depends on T001's exact two-key interface. Blocks T003. |

**Checkpoint**: US1 is independently demonstrable without ASC access: the contract test is green, XcodeGen is synchronized, Fastfile syntax is valid, and the unsigned Release build succeeds.

## Phase 2: User Story 2 - Detect signing drift before release (Priority: P1)

**Goal**: A frozen local candidate receives exact content review before unchanged publication with clean layer-scoped commits, then a fresh trusted review event proves the replacement shipping gate; real TestFlight validation stays separately blocked until Owner consent.

**Independent Test**: Run the focused and complete local gates, freeze the uncommitted tree, obtain exact AI Reviewer PASS and publication permission, prove the published replacement is the same tree with separate AppUI/RepoInfra commits, then verify a fresh post-#442 `pull_request_target` event returns a real schema-valid passing check without triggering TestFlight.

- [ ] T003 [US2] Assemble credential-free delivery evidence for `project.yml`, `VitalStride.xcodeproj/project.pbxproj`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`, and `.github/workflows/testflight.yml`

### T003 metadata

| Field | Contract |
|---|---|
| Owning layer | Cross-layer integration/delivery verification; no change-owner path or source commit |
| Context | `RepoInfra/CONTEXT.md`; `VitalStride/CONTEXT.md`; Constitution Development Workflow and Quality Bar J; DEC-026-006 |
| Vertical slice | `US2` credential-free freeze/review/replacement-publication proof |
| Files in scope | Verification-only access to `project.yml`, `VitalStride.xcodeproj/project.pbxproj`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`, `.github/workflows/testflight.yml`; frozen-tree manifest; after publication permission only, branch/commit and PR metadata |
| Files out of scope | Source repair inside T003; commit, push, or PR creation/update before permission; any PR #441 change before the replacement link exists; force-push/history rewrite; Developer Portal; ASC release operations; credentials; profile/certificate/keychain contents; real TestFlight dispatch |
| Interface impact | None. Verifies the assembled internal contract and delivery constraints. |
| Task-local acceptance | **Stage A — prepublication:** T001/T002 verification is fresh; AppUI baseline/profile components and the separate RepoInfra changes are frozen; no commit, push, or replacement PR publication has occurred; exact AI Reviewer content PASS and explicit publication permission identify that tree. Any content change invalidates permission. **Stage B — post-PASS:** the unchanged tree is committed as one AppUI commit followed by one RepoInfra commit, pushed on the new replacement branch, published as a non-Draft `owner-review` PR, and mapped with reviewed tree OID = published commit tree OID, while local commit SHA = remote branch OID = PR `headRefOid`. PR #441 remains unchanged until PR Manager closes it with the published replacement link. No TestFlight run is claimed or triggered. |
| Verification | Stage A, from repo root: rerun `quickstart.md` through unsigned Release; run `git diff --check`; inspect `.github/workflows/ci.yml` read-only for the unchanged PR gate; record frozen-tree manifest/hash and exact AI Reviewer verdict/permission. Stage B: record the two layer-scoped commits, non-Draft replacement URL, `owner-review` label, PR description, reviewed/published tree-OID equality, local commit/remote branch/PR-head commit-OID equality, PR Manager handoff, unchanged #441 evidence, and no TestFlight run URL. |
| Blocking edges | Depends on T001 and T002. Stage A blocks content review; PASS plus publication permission blocks Stage B; replacement publication enables T004 but does not satisfy it. |

- [ ] T004 [US2] After MY-1675 / PR #442 merges, obtain fresh trusted-review shipping evidence for the replacement through `.github/workflows/codex-review-target.yml`

### T004 metadata

| Field | Contract |
|---|---|
| Owning layer | External shipping verification; no repository layer, edit, or commit |
| Context | ADR-0020; Constitution Development Workflow and Quality Bar J; DEC-026-007 |
| Vertical slice | `US2` trusted required-review proof |
| Files in scope | Read-only trusted-base identity for `.github/workflows/codex-review-target.yml`; PR #442 merge/head/bootstrap evidence; replacement PR event, head, check-run, and schema-valid result metadata |
| Files out of scope | Editing the workflow or scripts; changing check identity; reusing #442's bootstrap; synthetic/manual success; stale/pre-fix event evidence; TestFlight dispatch; source repair |
| Interface impact | None. Proves the existing required review gate ran from the fixed trusted base on the replacement head. |
| Task-local acceptance | PR #442 first merged through the one-time human bootstrap bound to its exact authorized head; trusted base contains the #442 fix; the replacement then receives a fresh eligible `pull_request_target` event (`opened`, `synchronize`, or `reopened`) and a real schema-valid passing `codex-review-target` result for its current head. The #442 bypass and any stale, pre-fix, ineligible, or synthetic result are rejected. |
| Verification | Manual shipping evidence: PR #442 merge SHA and exact bootstrap-bound head; trusted-base workflow/script revision; replacement PR number/head; fresh event type/time/base SHA; `codex-review-target` check-run URL, app identity, head SHA, schema-valid result, and successful conclusion. PR Manager owns this evidence. |
| Blocking edges | Depends on T003 replacement publication and MY-1675 / PR #442 merge. Blocks replacement shipping; it does not block preparation and adds no implementation scope. |

- [ ] T005 [US2] After reviewed merge and explicit Owner consent, perform and record the single manual production validation through `.github/workflows/testflight.yml`

### T005 metadata

| Field | Contract |
|---|---|
| Owning layer | `RepoInfra` production-validation surface |
| Context | `RepoInfra/CONTEXT.md`; DEC-026-003 |
| Vertical slice | `US2` Owner-controlled production proof |
| Files in scope | Execution-only use of the existing `.github/workflows/testflight.yml`; no repository edit |
| Files out of scope | Any dispatch before consent; workflow/Fastfile/source changes; Developer Portal cleanup or certificate/profile revocation; secret/profile/certificate/keychain disclosure; automated publication |
| Interface impact | None. Exercises the already reviewed release path on `main`. |
| Task-local acceptance | Gate evidence proves: reviewed replacement merged to `main` after T004; explicit current Owner consent; non-Draft `owner-review` PR history; one manual workflow run using unchanged force semantics; terminal upload success; Apple processing completion; app/widget archive used the two in-run profiles; evidence contains no sensitive values or artifacts. |
| Verification | **Blocked until Owner consent.** Manual evidence form: Owner consent comment/decision ID, GitHub Actions run URL and head SHA on `main`, terminal conclusion, and processed TestFlight build identifier. Do not attach logs containing secrets, `.p8`, `.mobileprovision`, certificates, or keychain output. |
| Blocking edges | Depends on T004, replacement merge through PR Manager, and explicit Owner consent. Without consent it remains explicitly blocked and must not be dispatched. |

**Checkpoint**: US2 credential-free replacement publication can complete at T003; shipping requires T004. The issue's production outcome completes only when T005 receives consent and records processed-build evidence.

## Dependencies & Execution Order

```text
T001 AppUI baseline reconciliation + signing seam
  └─> T002 RepoInfra lane + regression
        └─> T003-A frozen-tree review + publication permission
              └─> T003-B clean AppUI/RepoInfra commits + replacement PR
                    ├─> PR Manager closes #441 with replacement link
                    └─> MY-1675 / PR #442 exact-head bootstrap merge
                          └─> T004 fresh pull_request_target + real passing codex-review-target
                                └─> PR Manager ships replacement
                                      └─> explicit Owner consent
                                            └─> T005 manual processed-build proof
```

- No implementation task spans AppUI and RepoInfra ownership.
- T001 and T002 each produce one layer-scoped implementation commit; the generated project is synchronized evidence inside T001, not a separate task or commit layer.
- T003 is verification/delivery-only and may not repair either owning layer; a failure routes to T001 or T002. T003-A forbids publication, and T003-B is unreachable without exact PASS and publication permission for the unchanged tree.
- T004 is an external shipping edge, not implementation scope. Preparation may proceed while it is blocked, but PR Manager cannot ship until the post-#442 real review result passes.
- T005 is not normal implementation verification and cannot be scheduled before replacement merge and its external Owner-consent edge.
- Team Lead reconciles and dispatches the reviewed graph; Planner Lead and AI Reviewer do not assign implementation roles.

## Acceptance Traceability

| Spec acceptance | Slice | Tasks | Verification surface |
|---|---|---|---|
| US1/AC5; FR-013; RB-004; SC-006 | US1 | T001 | `project.yml` support-resource exclusion, generated reference absence, same-executable idempotency |
| US1/AC1; FR-001, FR-003, FR-004 | US1 | T001, T002 | Static target/source mapping plus generated project |
| US1/AC2; FR-002 | US1 | T002 | Missing/empty/equal source regression and pre-archive failure contract |
| US1/AC3; FR-005 | US1 | T002 | Shell-safe opaque transport assertions |
| US1/AC4; FR-006, FR-007 | US1 | T001, T003 | XcodeGen sync and unsigned generic-iOS Release build |
| US2/AC1, US2/AC2; FR-008 | US2 | T002, T003 | Focused unittest and `bash scripts/test-repoinfra.sh` on the existing PR path |
| US2/AC3; FR-009, FR-011, FR-014 | US2 | T002, T003 | Preserved freshness tests; frozen-tree PASS; clean layer commits; replacement PR identity; #441 preservation |
| US2/AC4; FR-010 | US2 | T003, T005 | Absence of pre-consent dispatch; explicit blocked edge |
| US2/AC5; FR-012 | US2 | T005 | Consent record, run URL/head, terminal success, processed build identifier |
| US2/AC6; FR-015; SC-007 | US2 | T004 | #442 merge/bootstrap proof plus fresh eligible event and real passing schema-valid check result |
| RB-001; DEC-026-001 | US1 | T001, T002 | Fixed app/widget profile names absent; target-specific in-run values drive archive and export |
| RB-002; DEC-026-004 | US1 | T002 | Canonical-output missing/empty regression proves fail-closed behavior with no action-return fallback |
| RB-003; DEC-026-002 | US1/US2 | T002, T003 | Existing freshness assertions are preserved and the complete RepoInfra gate runs unchanged coverage plus the new regression |
| SC-001, SC-002 | US1/US2 | T002, T003 | Focused and full RepoInfra results |
| SC-003 | US1 | T001, T003 | XcodeGen synchronization and unsigned Release result |
| SC-004 | US2 | T003, T004 | PR Manager-owned required-check evidence |
| SC-005 | US2 | T005 | Owner-consented production evidence |

## Implementation Strategy

1. T001 first reconciles the support-resource baseline, then establishes the explicit signing interface in one AppUI commit and proves unsigned compatibility.
2. T002 writes the contract regression first, observes the historical state fail it, then repairs only RepoInfra until focused and complete gates pass.
3. T003-A freezes the uncommitted candidate; exact AI Reviewer content PASS and publication permission are required before T003-B publishes the unchanged tree as clean AppUI and RepoInfra commits on the replacement PR.
4. T004 waits for MY-1675 / PR #442, then proves the replacement's own fresh real required-review result; PR Manager ships only after this edge and the remaining required checks pass.
5. After replacement publication, PR Manager closes #441 with the replacement link; no force-push or history rewrite occurs.
6. T005 remains blocked unless and until the Owner explicitly authorizes the real upload; after consent it records only the approved production evidence.
