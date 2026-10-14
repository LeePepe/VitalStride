# Data Model: TestFlight auto-release state

This feature introduces no product persistence. Workflow state is ephemeral; `testflight/last-released` is the only durable release state.

## CandidateRelease

| Field | Contract |
|---|---|
| `sha` | Exact automatic `workflow_run.head_sha` or exact current remote `main` captured for manual dispatch |
| `source` | `automatic-ci` or `manual` |
| `ci_workflow/event/branch/conclusion` | Automatic only: exact `CI` / `push` / `main` / `success` |
| `run_url` | Safe GitHub Actions URL for summary/evidence |

**Invariant**: Candidate identity is immutable after capture; checkout, marker relation, diff, PR lookup, lane inputs, and evidence use the same SHA.

## ReleaseMarker

| Ref | Meaning | Transition |
|---|---|---|
| `testflight/last-released` | Latest candidate whose full critical lane and marker readback succeeded | Absent initially; otherwise move to candidate only as the final critical step |

**Invariants**:

- It is the sole durable state; no attempt/skip history, queue/cursor, transaction journal, lease, or recovery ref exists.
- Absence selects the Git empty tree as an ephemeral bootstrap baseline.
- Marker ancestor of candidate permits accumulated classification; equality or candidate ancestor of marker is already covered; divergence/invalidity fails closed.
- Every pre-marker critical failure invokes no marker mutation.
- Marker update/readback failure is terminal, writes no auxiliary state, performs no retry/rollback, and makes no claim about an unobservable remote acknowledgement. The next run re-fetches the marker.

## EligibilityDecision

| Field | Values |
|---|---|
| `candidate_sha` | CandidateRelease SHA |
| `marker_sha` | Remote marker SHA, or `absent` |
| `baseline_sha` | Marker SHA or ephemeral Git empty tree |
| `relation` | `bootstrap`, `ahead`, `already-covered`, or `invalid` |
| `force` | Manual boolean; automatic is false |
| `change_records` | NUL-safe add/modify/delete/rename/copy records; rename/copy retains endpoints |
| `relevant_paths` | Records with at least one non-excluded positive endpoint |
| `decision` | `release`, `skip-ineligible`, `skip-already-covered`, or `fail` |
| `reason_code` | Stable non-secret summary/dashboard classifier |

**Invariant**: Force changes only `skip-ineligible` to `release`; it cannot override current-main identity, already-covered/invalid relation, PR/version, signing, or critical-lane failures.

## VersionDecision

| Field | Contract |
|---|---|
| `project_version` | Uniform numeric shipping-target version from `project.yml` |
| `associated_pr` | Exactly one merged PR for the exact candidate, based on `main` |
| `minor_label` | Exact case-sensitive `release:minor` on that candidate PR only |
| `marketing_version` | Project version, or per-run next minor with existing patch reset to zero |
| `build_number` | App Store Connect app-wide maximum plus one |

**Invariants**: No checkout edit; one marketing value is reused by archive/lookup/distribution/evidence; build lookup is not marketing-version-filtered.

## ReleaseEvidence

| Field | Required for |
|---|---|
| Exact SHA, source, run URL | skip, failure, success |
| Relation/decision or failed phase and reason code | skip, failure |
| Baseline and last safely observed marker | marker-related skip/failure/success |
| Marketing version and build number | release attempt/success after derivation |
| Confirmed marker equals candidate | final success and MY-1766 evidence |
| Terminal conclusion | MY-1766 evidence |

**Excluded**: secret/API-key/keychain/certificate/profile values or names, unredacted credential logs, and health values.

## MarkerUpdate

| Field | Contract |
|---|---|
| `baseline_sha` | Marker observed for eligibility, or absent bootstrap |
| `candidate_sha` | Exact CandidateRelease SHA |
| `update_phase` | Invoked only after all other critical phases succeed |
| `push_result` | Safe success/failure result, without credentials |
| `readback_sha` | Fresh remote marker SHA or unavailable |
| `terminal_state` | `confirmed-candidate` or `failed` |

**Invariant**: Only exact candidate readback is terminal success. Failure creates no second durable record and triggers no automatic overwrite, retry, or rollback.

## State Transitions

```text
EVENT_RECEIVED
  -> SOURCE_REJECTED
  -> CANDIDATE_CAPTURED
       -> MARKER_BOOTSTRAP (empty-tree baseline)
       -> ALREADY_COVERED (skip)
       -> MARKER_INVALID (fail)
       -> RANGE_READY
            -> PATH_INELIGIBLE (skip unless manual force)
            -> PR_OR_VERSION_INVALID (fail)
            -> RELEASE_READY
                 -> CRITICAL_PHASE_FAILED (fail; no marker command)
                 -> CRITICAL_LANE_COMPLETE
                      -> MARKER_UPDATE_OR_READBACK_FAILED (fail; no auxiliary state/retry/rollback)
                      -> RECORDED_SUCCESS (remote marker equals candidate)
```

Skipped and failed ranges persist only through the unchanged marker. A later successful main-CI event or manual dispatch starts a new evaluation; it is not an automatic retry transition.
