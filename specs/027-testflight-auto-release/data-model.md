# Data Model: Minimal automatic TestFlight release

This workflow has one durable repository value: `testflight/last-released`. All other values are run-local.

## AutomaticCandidate

| Field | Contract |
|---|---|
| `workflow_name` | exactly `CI` |
| `conclusion` | exactly `success` |
| `source_event` | exactly `push` |
| `head_branch` | exactly `main` |
| `head_sha` | captured once from the accepted `workflow_run`; used for checkout, diff, lane context, and marker target |

**Invariant**: no later read of moving `main` replaces `head_sha`.

## ReleaseMarker

| Field | Contract |
|---|---|
| `ref` | exactly `testflight/last-released` |
| `baseline_sha` | remote marker commit observed before classification |
| `candidate_sha` | accepted AutomaticCandidate `head_sha` |
| `valid` | marker resolves to a commit that is an ancestor of candidate |

**Invariant**: invalid or missing marker state fails before lane invocation. No second durable release ref exists.

## RelevanceDecision

| Field | Contract |
|---|---|
| `range` | `baseline_sha..candidate_sha` |
| `change_records` | NUL-safe add/modify/delete/rename/copy records; rename/copy retains endpoints |
| `relevant_paths` | endpoints that pass exclusion precedence and an accepted positive predicate |
| `decision` | `release`, `skip`, or `fail` |

**Invariants**:

- one relevant endpoint makes the range relevant;
- relevant deletion qualifies;
- an irrelevant range leaves the marker unchanged;
- no relevance result is persisted separately.

## LaneOutcome

| Field | Contract |
|---|---|
| `candidate_sha` | exact accepted candidate |
| `invocation` | existing `fastlane ios beta` lane |
| `upload_result` | success or failure from the existing lane |
| `marker_step_reached` | true only after lane success |
| `terminal_result` | skipped, failed, or marker-update attempted after successful upload |

**Invariants**:

- lane failure cannot reach marker update;
- no automatic retry or rollback is configured;
- no shadow model of signing, version, build number, processing, distribution, dSYM, telemetry, or recovery is introduced.

## State transitions

```text
WORKFLOW_RUN
  -> SOURCE_REJECTED
  -> CANDIDATE_CAPTURED
       -> MARKER_INVALID (fail; marker unchanged)
       -> RANGE_CLASSIFIED
            -> IRRELEVANT (skip; marker unchanged)
            -> RELEVANT
                 -> EXISTING_LANE_FAILED (fail; marker unchanged)
                 -> UPLOAD_SUCCEEDED
                      -> MOVE_LAST_RELEASED_TO_CANDIDATE
```

There is no automatic transition from failure back to execution. A later qualifying `workflow_run` is a new run and re-evaluates the then-current sole marker.
