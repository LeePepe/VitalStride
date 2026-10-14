# Data Model: TestFlight auto-release state

This feature introduces no product persistence. The model describes ephemeral workflow state, one moving success marker, immutable per-SHA Git attempt claims, and immutable per-SHA success-pending/resolved pairs that durably gate marker recovery.

## CandidateRelease

| Field | Contract |
|---|---|
| `sha` | Exact 40-character automatic `workflow_run.head_sha` or exact current `main` SHA captured for manual dispatch |
| `source` | `automatic-ci` or `manual` |
| `ci_workflow` | Automatic only: exact `CI` |
| `ci_event` | Automatic only: `push` |
| `ci_branch` | Automatic only: `main` |
| `ci_conclusion` | Automatic only: `success` |
| `run_url` | Safe GitHub Actions URL used in summary/evidence |

**Invariant**: Candidate identity is immutable after capture; checkout, diff, PR lookup, markers, lane inputs, and evidence use the same SHA.

## ReleaseMarkers and AttemptClaims

| Ref | Meaning | Transition |
|---|---|---|
| `testflight/attempted/<SHA>` | Immutable evidence that exact SHA crossed the irreversible release-attempt boundary | Create without force and remotely confirm immediately before the lane; never move/delete/roll back |
| `testflight/success-pending/<SHA>` | Immutable evidence that all earlier critical phases completed and success-marker mutation is starting | Create without force and remotely confirm immediately before marker mutation; never move/delete/roll back |
| `testflight/success-resolved/<SHA>` | Immutable evidence that the matching pending marker transaction was safely reconciled | Automatic path creates/confirms only after exact candidate marker readback; Owner recovery may create/confirm after one defined disposition; an ambiguous automatic confirmation fails that run and is re-observed by later preflight; never move/delete/roll back |
| `testflight/last-released` | Latest SHA whose complete critical release path succeeded | Mutate toward the candidate and remotely confirm only after upload, processing, distribution, and dSYM publication succeed |

**Invariants**:

- Candidate equal to the successful marker or with an existing immutable attempt claim is not uploaded.
- Claims for older SHAs remain effective after later claims; A→B→A can never re-enter the lane.
- Successful marker must be an ancestor of a new candidate before accumulated diff classification.
- Failures before success-marker mutation leave it unchanged.
- A failed/unavailable success-marker confirmation after mutation enters `success-marker-indeterminate`; no unchanged-state assertion or rollback is allowed.
- Failed, existing, or unconfirmed claim creation occurs before archive/upload.
- Every pending/resolved ref name is well formed and its target equals the SHA encoded in the name. A malformed name, mismatched target, or orphan resolved ref fails closed before upload.
- Any confirmed `success-pending/<SHA>` without matching `success-resolved/<SHA>` is durable recovery-required state and blocks every candidate before upload. An exact valid pair clears only that preflight gate; it does not rewrite a prior failed run as success evidence.
- A resolved ref is created automatically only after exact candidate readback; exceptional Owner recovery creates it only after recording one defined disposition. Ambiguous automatic creation/confirmation fails the current run without asserting pair state; the next authoritative preflight determines exact-valid, confirmed-absent, or invalid state. Pending/resolved refs are never moved or deleted.

## EligibilityDecision

| Field | Values |
|---|---|
| `candidate_sha` | CandidateRelease SHA |
| `baseline_sha` | Resolved successful marker SHA |
| `force` | Manual boolean; automatic is false |
| `changed_paths` | Names from `baseline..candidate` |
| `relevant_paths` | Intersection with the exact app-relevant allowlist |
| `change_records` | NUL-safe add/modify/delete/rename/copy records; rename/copy retains both endpoints |
| `decision` | `release`, `skip-ineligible`, `skip-duplicate`, `skip-attempted`, or `fail` |
| `reason_code` | Stable non-secret classifier for summary/dashboard, including `success-marker-recovery-required` and `success-marker-indeterminate` |

**Invariant**: Force changes only `skip-ineligible` to `release`; it cannot override marker, identity, ancestry, PR/version, or claim failures.

## VersionDecision

| Field | Contract |
|---|---|
| `project_version` | One uniform numeric major/minor or major/minor/patch value read from shipping targets in `project.yml` |
| `associated_pr` | Automatic and manual: exactly one merged PR for candidate, based on `main` |
| `minor_label` | Exact case-sensitive presence of `release:minor` |
| `marketing_version` | Project version, or its minor increment with existing patch reset to zero |
| `build_number` | App Store Connect app-wide maximum plus one |

**Invariants**:

- Marketing-version derivation does not edit the checkout.
- Archive, upload lookup, distribution, summary, and issue evidence share the same resolved value.
- Build-number lookup is never filtered by marketing version.

## ReleaseEvidence

| Field | Required for |
|---|---|
| Exact SHA, source, run URL | skip, failure, success |
| Decision or failed phase and reason code | skip, failure |
| Marketing version and build number | attempt/success after derivation |
| Immutable attempt claim, success-pending/resolved pair, plus successful-marker observation/state | final success and MY-1766 evidence |
| Terminal conclusion | MY-1766 evidence |

**Excluded**: secret values, API key material, keychain data, certificates, profile contents/names, raw logs containing credentials, and health values.

## SuccessMarkerMutation

| Field | Contract |
|---|---|
| `prior_oid` | Freshly read and confirmed `testflight/last-released` OID captured before release |
| `candidate_oid` | Exact CandidateRelease SHA |
| `lease_result` | `accepted`, `rejected`, or `unknown` |
| `readback_oid` | Fresh remote value, or `unreadable` |
| `state` | `confirmed-candidate`, `confirmed-prior`, `conflict`, or `indeterminate` |
| `pending_ref` | Confirmed immutable `testflight/success-pending/<candidate>` created before mutation |
| `resolved_ref` | Matching immutable `testflight/success-resolved/<candidate>` with observation `confirmed`, `confirmed-absent`, or `indeterminate`; confirmed absence means recovery remains required |

**Invariant**: Mutation begins only after `pending_ref` confirmation and uses `prior_oid` as its compare-and-swap/lease expectation. Only `readback_oid == candidate_oid` followed by confirmed `resolved_ref` is automatic success in that run. Ambiguous resolution confirmation is failure without a pair-state assertion; a later exact valid pair clears only the recovery gate and never retroactively changes the terminal result. No automatic overwrite, rewind, rollback, or exceptional resolution write follows any other state.

## State Transitions

```text
EVENT_RECEIVED
  -> SOURCE_REJECTED (automatic non-CI/non-push/non-main/non-success)
  -> CANDIDATE_CAPTURED
       -> SUCCESS_REF_NAMESPACE_INVALID (fail closed on malformed names, mismatched targets, or orphan resolved refs)
       -> UNRESOLVED_SUCCESS_PENDING (fail before upload when a confirmed pending ref has no matching resolved ref)
       -> VALID_SUCCESS_PAIR_OBSERVED (clear only the recovery gate; do not revise prior run evidence)
       -> DUPLICATE_OR_ATTEMPTED (skip)
       -> MARKER_INVALID (fail)
       -> PATH_INELIGIBLE (skip unless manual force)
       -> PR_OR_VERSION_INVALID (fail for automatic or manual)
       -> CLAIMING
            -> CLAIM_FAILED_OR_INDETERMINATE (fail before upload; future evaluation checks durable ref)
            -> ATTEMPTED
                 -> RELEASE_PHASE_FAILED (before success-marker mutation; claim retained; prior marker preserved)
                 -> RELEASE_SUCCEEDED
                      -> SUCCESS_PENDING_CREATE_OR_CONFIRM_FAILED (fail; remote may be absent/pending; future preflight enforces any observed pending)
                      -> SUCCESS_PENDING_CONFIRMED
                           -> SUCCESS_MARKER_FAILED (lease rejected or confirmed prior value; fail; claim prevents duplicate)
                           -> SUCCESS_MARKER_CONFLICT (different remote SHA; fail; no overwrite; Owner recovery required)
                           -> SUCCESS_MARKER_INDETERMINATE (remote value unknown/maybe moved; fail; Owner recovery required)
                           -> SUCCESS_MARKER_CONFIRMED
                                -> SUCCESS_RESOLUTION_FAILED (confirmed absent; fail; pending is unpaired; Owner recovery required)
                                -> SUCCESS_RESOLUTION_INDETERMINATE (fail current run; do not assert pair state; next authoritative preflight decides)
                                -> RECORDED_SUCCESS (matching resolved ref confirmed)
```

There is no retry or rollback transition. At every authoritative preflight, each pending/resolved ref must be well formed and target its encoded SHA. An exact valid pair clears only the recovery gate; a confirmed unpaired pending ref blocks later candidates for Owner recovery; malformed, mismatched, or orphan state fails closed. Ambiguous resolution confirmation in the prior run is not evidence of either pairing state and never becomes product-success evidence; its exact-valid observation may clear the gate, while confirmed absence enters Owner recovery. Success-marker conflict/indeterminate and confirmed-unpaired states may leave only through Owner recovery that reads the remote ref and records one disposition: candidate (reconcile without upload), prior baseline (verify ASC evidence before any Owner-authorized leased forward advance), another SHA (reconcile ordering without overwrite), or unreadable/invalid (remain blocked). The first three dispositions create and remotely confirm the matching immutable resolved ref only after their safe evidence is recorded; the unreadable/invalid disposition leaves it absent. Recovery never retries the claimed SHA or deletes/moves either ref.
