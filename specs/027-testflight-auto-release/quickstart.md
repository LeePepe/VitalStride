# Quickstart: TestFlight auto-release implementation verification

## Preconditions

- Work from the exact Team Lead-approved implementation base containing the independently reviewed `specs/027-testflight-auto-release/**` revision.
- Confirm the implementation diff is limited to `.github/workflows/testflight.yml`, `fastlane/Fastfile`, and `scripts/tests/test_testflight_freshness.py`.
- Treat `testflight/last-released` as the only durable release state; do not add an attempt/skip ref, queue/cursor, lease/CAS record, journal, pending/resolved ref, or recovery ref.
- Do not dispatch TestFlight, read secret values, mutate tags, or contact App Store Connect during local verification.
- Publication of `.github/workflows/testflight.yml` requires explicit Owner approval; content review and CI do not grant it.

## Red-first contract cycle

1. Add credential-free tests for the selected task contract.
2. Run the focused suite and capture the expected contract failure before production edits.
3. Change only the task-owned RepoInfra paths.
4. Rerun until the focused suite reports zero failures/errors.

## Required local evidence

From repository root:

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
ruby -c fastlane/Fastfile
bash scripts/test-repoinfra.sh
git diff --check
git status --short
```

Read the full RepoInfra output. Exit code alone is insufficient because the planning environment previously exposed nested Python failures while the wrapper returned zero.

No `xcodebuild` or package build/test is part of this RepoInfra-only verification. If the diff enters AppUI or `Packages/**`, stop as out of scope instead of expanding the command set.

## Static inspection

- Automatic candidate is the exact successful `CI` push/main head SHA; manual candidate is current remote `main` captured once.
- Full-history/tag fetch precedes marker and diff decisions.
- Missing marker selects the Git empty tree ephemerally; marker-ancestor selects `marker..candidate`; equal or marker-ahead candidates skip as already covered; invalid/divergent markers fail closed.
- NUL-safe path classification uses the contract's narrow positives and endpoint-first exclusions. Package tests/contexts and documentation remain negative; relevant deletion, mixed diffs, and either relevant rename/copy endpoint qualify.
- Skips and pre-marker failures write no durable state. A later executed candidate sees every still-unreleased change through the unchanged marker range.
- One app-scoped group has `cancel-in-progress: false`; no custom durable queue or FIFO promise is introduced.
- Manual `force=true` bypasses relevance only. It cannot bypass current-main identity, already-covered/invalid marker state, candidate PR/version resolution, signing, or a critical failure.
- Automatic and manual candidates use the same exact candidate-PR and case-sensitive `release:minor` policy. Earlier PR labels in the accumulated range do not apply.
- One resolved marketing version is reused across archive, lookup, distribution, and evidence. The build-number query remains app-wide and its selected value reaches safe evidence.
- Every earlier critical phase succeeds before the sole marker mutation command can run. Exact fresh `testflight/last-released` readback is required for success.
- Marker update/readback failure is terminal, creates no auxiliary state, performs no retry/rollback, and makes no assertion about an unobservable remote acknowledgement; a later invocation freshly reads the remote marker.
- Existing runner, dynamic profile/signing, secret names, processing wait, internal group, telemetry inputs, and non-secret logging boundaries remain.
- Only the three implementation paths changed.

## Review and publication evidence

- Freeze the exact local candidate and capture its SHA, tree, three-path manifest, and fresh verification output.
- Obtain independent AI Reviewer content verdict for that exact candidate under the Dev Team pre-publication flow.
- Publish only the reviewed candidate through the normal non-Draft PR path.
- Record explicit Owner approval for the `.github/**` change before merge.
- PR Manager owns required-check and merge/shipping state; Team Lead owns scheduling, recovery, and exceptions.

## Post-merge operational evidence

For the first eligible successful main-CI candidate, record on MY-1766:

- exact candidate/CI SHA;
- TestFlight workflow run URL and terminal conclusion;
- runtime marketing version and unique build number;
- freshly confirmed remote `testflight/last-released` equal to the candidate.

Do not attach secrets, `.p8` material, profiles, certificates, keychain output, health values, or unredacted sensitive logs.

A failed run is incident evidence only and does not complete T005 or MY-1766 outcome acceptance. The marker-only contract configures no automatic retry or rollback. A later eligible main-CI event or manual current-main dispatch is a new evaluation of the then-current remote marker and accumulated range.
