# Data Model: TestFlight auto-release state

This feature introduces no product persistence. The model describes ephemeral workflow state plus two durable Git markers.

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

## ReleaseMarkers

| Marker | Meaning | Transition |
|---|---|---|
| `testflight/last-attempted` | Latest SHA that crossed the irreversible release-attempt boundary | Move and remotely confirm immediately before the lane; never roll back on failure |
| `testflight/last-released` | Latest SHA whose complete critical release path succeeded | Move and remotely confirm only after upload, processing, distribution, and dSYM publication succeed |

**Invariants**:

- Candidate equal to either marker is not uploaded.
- Successful marker must be an ancestor of a new candidate before accumulated diff classification.
- Failed or uncertain attempt leaves the success marker unchanged.
- Claim-write failure occurs before archive/upload.

## EligibilityDecision

| Field | Values |
|---|---|
| `candidate_sha` | CandidateRelease SHA |
| `baseline_sha` | Resolved successful marker SHA |
| `force` | Manual boolean; automatic is false |
| `changed_paths` | Names from `baseline..candidate` |
| `relevant_paths` | Intersection with the exact app-relevant allowlist |
| `decision` | `release`, `skip-ineligible`, `skip-duplicate`, `skip-attempted`, or `fail` |
| `reason_code` | Stable non-secret classifier for summary/dashboard |

**Invariant**: Force changes only `skip-ineligible` to `release`; it cannot override marker, identity, ancestry, PR/version, or claim failures.

## VersionDecision

| Field | Contract |
|---|---|
| `project_version` | One uniform numeric major/minor or major/minor/patch value read from shipping targets in `project.yml` |
| `associated_pr` | Automatic only: exactly one merged PR for candidate, based on `main` |
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
| Attempted and successful marker SHAs | final success and MY-1766 evidence |
| Terminal conclusion | MY-1766 evidence |

**Excluded**: secret values, API key material, keychain data, certificates, profile contents/names, raw logs containing credentials, and health values.

## State Transitions

```text
EVENT_RECEIVED
  -> SOURCE_REJECTED (automatic non-CI/non-push/non-main/non-success)
  -> CANDIDATE_CAPTURED
       -> DUPLICATE_OR_ATTEMPTED (skip)
       -> MARKER_INVALID (fail)
       -> PATH_INELIGIBLE (skip unless manual force)
       -> PR_OR_VERSION_INVALID (fail)
       -> CLAIMING
            -> CLAIM_FAILED (fail before upload)
            -> ATTEMPTED
                 -> RELEASE_FAILED (claim retained; success marker unchanged)
                 -> RELEASE_SUCCEEDED
                      -> SUCCESS_MARKER_FAILED (fail; claim prevents duplicate)
                      -> RECORDED_SUCCESS
```

There is no retry or rollback transition.
