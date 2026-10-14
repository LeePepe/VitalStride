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
| Interface impact | Consumes the two T001 keys. Resolves the existing canonical app/widget profile-name sources once; rejects absent/nil and whitespace-only values through a validation-only stripped view; shell-safely transports each original nonblank raw value verbatim to archive; and reuses the same original variables in export. Removes the action-return fallback. No workflow input or public product signature change. |
| Task-local acceptance | In a separate RepoInfra commit after T001, add tests before T002 production edits. Use the exact immutable-base overlay procedure below to demonstrate that the full historical fixed-name/fallback state violates the candidate test without reverting T001. Preserve the existing four freshness cases; both forced installed fetches remain; absent/nil, whitespace-only, and equal preserved raw values fail before `build_app`; distinct nonblank names with leading/trailing/embedded whitespace or shell-significant characters are preserved verbatim, shell-safe, and target-correct; export reuses archive variables; no fixed name, fallback, global profile override, credential read, signing, upload, or external mutation occurs in tests. |
| Verification | From repo root, first run and capture the immutable-base historical-red procedure below; require nonzero for both fixed-name and action-fallback assertions, not import/fixture failure. Then run final green separately: `python3 -B -m unittest scripts.tests.test_testflight_freshness`; `ruby -c fastlane/Fastfile`; `bash scripts/test-repoinfra.sh`; `git diff --check` |
| Blocking edges | Depends on T001's exact two-key interface. Blocks T003. |

#### T002 ordered historical-red procedure

After authoring `scripts/tests/test_testflight_freshness.py` but before changing the Fastfile or workflow comments, execute:

```bash
(
  set -o pipefail
  red_fixture="$(mktemp -d "${TMPDIR:-/tmp}/my1660-red.XXXXXX")" || exit 1
  test -d "$red_fixture" || exit 1
  case "$red_fixture" in
    */my1660-red.*) ;;
    *) exit 1 ;;
  esac
  red_log="$red_fixture/historical-red.log"
  cleanup_red_fixture() {
    case "${red_fixture:-}" in
      */my1660-red.*) rm -rf -- "$red_fixture" ;;
    esac
  }
  trap cleanup_red_fixture EXIT HUP INT TERM
  git archive e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b -- \
    .github/workflows/testflight.yml fastlane/Fastfile project.yml \
    | tar -x -C "$red_fixture" || exit 1
  mkdir -p "$red_fixture/scripts/tests" || exit 1
  cp scripts/tests/test_testflight_freshness.py \
    "$red_fixture/scripts/tests/test_testflight_freshness.py" || exit 1
  if (
    cd "$red_fixture" || exit 1
    python3 -B -m unittest scripts.tests.test_testflight_freshness
  ) >"$red_log" 2>&1; then
    printf '%s\n' 'historical fixed-name/fallback fixture unexpectedly passed' >&2
    exit 1
  else
    red_status=$?
  fi
  awk '{ print }' "$red_log"
  test "$red_status" -ne 0 || exit 1
  rg -F 'HISTORICAL_FIXED_PROFILE_NAMES_REJECTED' "$red_log" >/dev/null || exit 1
  rg -F 'HISTORICAL_ACTION_RETURN_FALLBACK_REJECTED' "$red_log" >/dev/null || exit 1
)
```

The candidate assertions must emit stable markers `HISTORICAL_FIXED_PROFILE_NAMES_REJECTED` and `HISTORICAL_ACTION_RETURN_FALLBACK_REJECTED`. The guarded command accepts red proof only when the unittest run is nonzero and both markers appear; setup, import, fixture, and unrelated failures are rejected. The overlay exports all three inspected production surfaces from the immutable source base, so T001 remains applied in the real working tree and the AppUI→RepoInfra order is preserved. Run the final-green commands in the repaired working tree only after the RepoInfra edits.

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
| Blocking edges | Depends on T001 and T002. Stage A blocks content review; PASS plus publication permission blocks Stage B; replacement publication supplies one of T004's two independent prerequisites but does not satisfy the join. |

- [ ] T004 [US2] After MY-1675 / PR #442 merges, obtain fresh trusted-review shipping evidence for the replacement through `.github/workflows/codex-review-target.yml`

### T004 metadata

| Field | Contract |
|---|---|
| Owning layer | External shipping verification; no repository layer, edit, or commit |
| Context | ADR-0020; Constitution Development Workflow and Quality Bar J; DEC-026-007 |
| Vertical slice | `US2` trusted required-review proof |
| Files in scope | Read-only trusted event-base identity for `.github/workflows/codex-review-target.yml`; immutable replacement source-base identity; PR #442 merge/head/bootstrap evidence; replacement PR event, head, check-run, and schema-valid result metadata |
| Files out of scope | Editing the workflow or scripts; changing check identity; reusing #442's bootstrap; synthetic/manual success; stale/pre-fix event evidence; TestFlight dispatch; source repair |
| Interface impact | None. Proves the existing required review gate ran on the replacement head from the fresh event's trusted `github.event.pull_request.base.sha` on `main`, while replacement ancestry remains rooted at the distinct immutable source base. |
| Task-local acceptance | Two independent prerequisites converge: T003-B published the replacement whose ancestry remains rooted at `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`, and PR #442 merged through the one-time human bootstrap bound to its exact authorized head so `main` contains the fix. The replacement then receives a fresh eligible `pull_request_target` event (`opened`, `synchronize`, or `reopened`) whose `github.event.pull_request.base.sha` is that fixed `main` revision, and a real schema-valid passing `codex-review-target` result for its current head. The event-base advance does not authorize rebase/history rewrite; the #442 bypass and any stale, pre-fix, ineligible, or synthetic result are rejected. |
| Verification | Manual shipping evidence: immutable replacement source-base SHA; PR #442 merge SHA and exact bootstrap-bound head; trusted event-base `main` SHA and workflow/script revision; replacement PR number/head; fresh event type/time/base SHA; `codex-review-target` check-run URL, app identity, head SHA, schema-valid result, and successful conclusion. PR Manager owns this evidence. |
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
              └─> T003-B clean AppUI/RepoInfra commits + replacement PR ───┐
                    └─> PR Manager closes #441 with replacement link      │
MY-1675 / PR #442 exact-head bootstrap merge                              │
  └─> fresh event base/default-branch SHA on main contains #442 fix ──────┤
                                                                          └─> T004 fresh pull_request_target + real passing codex-review-target
                                                                                └─> PR Manager ships replacement
                                                                                      └─> explicit Owner consent
                                                                                            └─> T005 manual processed-build proof
```

- No implementation task spans AppUI and RepoInfra ownership.
- T001 and T002 each produce one layer-scoped implementation commit; the generated project is synchronized evidence inside T001, not a separate task or commit layer.
- T003 is verification/delivery-only and may not repair either owning layer; a failure routes to T001 or T002. T003-A forbids publication, and T003-B is unreachable without exact PASS and publication permission for the unchanged tree.
- T004 is an external shipping join, not implementation scope. T003-B publication and the independent #442 merge/fixed-`main` event-base prerequisite may progress in parallel; PR Manager cannot ship until they converge and the post-#442 real review result passes without changing replacement source ancestry.
- T005 is not normal implementation verification and cannot be scheduled before replacement merge and its external Owner-consent edge.
- Team Lead reconciles and dispatches the reviewed graph; Planner Lead and AI Reviewer do not assign implementation roles.

## Acceptance Traceability

| Spec acceptance | Slice | Tasks | Verification surface |
|---|---|---|---|
| US1/AC5; FR-013; RB-004; SC-006 | US1 | T001 | `project.yml` support-resource exclusion, generated reference absence, same-executable idempotency |
| US1/AC1; FR-001, FR-003, FR-004 | US1 | T001, T002 | Static target/source mapping plus generated project |
| US1/AC2; FR-002 | US1 | T002 | Absent/nil, whitespace-only, and equal-preserved-raw-value regression plus pre-`build_app` failure contract |
| US1/AC3; FR-005 | US1 | T002 | Nonblank leading/trailing/embedded-whitespace and shell-significant values preserved verbatim through target-specific transport |
| US1/AC4; FR-006, FR-007 | US1 | T001, T003 | XcodeGen sync and unsigned generic-iOS Release build |
| US2/AC1, US2/AC2; FR-008 | US2 | T002, T003 | Captured immutable-base overlay red proof, then focused unittest and `bash scripts/test-repoinfra.sh` green on the repaired PR path |
| US2/AC3; FR-009, FR-011, FR-014 | US2 | T002, T003 | Preserved freshness tests; frozen-tree PASS; clean layer commits; replacement PR identity; #441 preservation |
| US2/AC4; FR-010 | US2 | T003, T005 | Absence of pre-consent dispatch; explicit blocked edge |
| US2/AC5; FR-012 | US2 | T005 | Consent record, run URL/head, terminal success, processed build identifier |
| US2/AC6; FR-015; SC-007 | US2 | T004 | Immutable replacement source base plus independent #442 merge/bootstrap and fixed-`main` trusted event-base proof, joined by fresh eligible event and real passing schema-valid check result |
| RB-001; DEC-026-001 | US1 | T001, T002 | Fixed app/widget profile names absent; target-specific in-run values drive archive and export |
| RB-002; DEC-026-004 | US1 | T002 | Canonical-output absent/nil/whitespace-only regression proves fail-closed behavior with no action-return fallback or raw-value mutation |
| RB-003; DEC-026-002 | US1/US2 | T002, T003 | Existing freshness assertions are preserved and the complete RepoInfra gate runs unchanged coverage plus the new regression |
| SC-001, SC-002 | US1/US2 | T002, T003 | Focused and full RepoInfra results |
| SC-003 | US1 | T001, T003 | XcodeGen synchronization and unsigned Release result |
| SC-004 | US2 | T003, T004 | PR Manager-owned required-check evidence |
| SC-005 | US2 | T005 | Owner-consented production evidence |

## Implementation Strategy

1. T001 first reconciles the support-resource baseline, then establishes the explicit signing interface in one AppUI commit and proves unsigned compatibility.
2. T002 writes the contract regression first, runs it against the exact immutable-base overlay to observe both historical fixed-name and fallback failures without reverting T001, then repairs only RepoInfra until focused and complete gates pass.
3. T003-A freezes the uncommitted candidate; exact AI Reviewer content PASS and publication permission are required before T003-B publishes the unchanged tree as clean AppUI and RepoInfra commits on the replacement PR.
4. T003-B publication and MY-1675 / PR #442 merge progress independently. T004 joins them at a fresh event whose trusted `main` base SHA contains #442 while replacement ancestry remains unchanged, then proves the replacement's own real required-review result; PR Manager ships only after this edge and the remaining required checks pass.
5. After replacement publication, PR Manager closes #441 with the replacement link; no force-push or history rewrite occurs.
6. T005 remains blocked unless and until the Owner explicitly authorizes the real upload; after consent it records only the approved production evidence.
