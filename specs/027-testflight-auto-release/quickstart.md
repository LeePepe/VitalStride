# Quickstart: Minimal automatic TestFlight release verification

## Preconditions

- Work only in the registered delivery workspace and branch supplied by Team Lead.
- Base implementation on the exact independently reviewed v3 planning revision.
- Confirm repository identity, branch, base, and local candidate before mutation.
- Confirm the candidate changes only `.github/workflows/testflight.yml` and `scripts/tests/test_testflight_freshness.py`; `fastlane/Fastfile` remains unchanged.
- Treat `testflight/last-released` as the only durable release state.
- Do not dispatch TestFlight, mutate a tag, read secret values, sign, or contact App Store Connect during local verification.
- Ensure `actionlint` is available as an executor prerequisite.
- Preserve the explicit Owner approval boundary for the workflow.

## Red-first implementation cycle

1. Trim the existing test module to the v3 classifier contract.
2. Add cases for source/candidate, literal marker range, accepted/excluded paths, lane decision, post-upload marker ordering, concurrency/permission, and forbidden auxiliary state.
3. Run the focused unit test against the unmodified workflow and retain the expected failures.
4. Modify only the workflow and classifier test.
5. Rerun the two feature-specific commands until both succeed.

## Complete local verification

From repository root, run the two feature-specific checks:

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
actionlint .github/workflows/testflight.yml
```

These are the only feature-specific v3 checks. Read their full output.

Then run the independently mandatory repository gate:

```bash
bash scripts/test-repoinfra.sh
```

Read its full output and require zero failures/errors; exit code alone is insufficient. This gate is not a third feature-specific check and does not restore v2 shadow-policy acceptance.

Do not add standalone Ruby syntax, XcodeGen, xcodebuild, SwiftPM, Fastlane execution, signing/profile feature checks, upload, tag mutation, production evidence, or any feature-specific shadow-policy suite.

## Candidate inspection

Record, without running another product gate:

- automatic source is exact successful `CI` / `push` / `main`;
- checkout, diff, lane context, and marker target reuse `workflow_run.head_sha`;
- the diff range is exactly `testflight/last-released..candidate`;
- path classification matches the contract's exact positives and exclusions;
- irrelevant range skips and invalid marker fails before lane;
- relevant range invokes the unchanged `fastlane ios beta` lane;
- marker update follows successful lane/upload and targets the candidate;
- failures before marker update do not reach it;
- one group has `cancel-in-progress: false`;
- the release job declares `contents: write`;
- no per-SHA/second-marker/queue/cursor/CAS/lease/journal/pending/resolved/recovery state, automatic retry, rollback, or second lane exists;
- candidate manifest is exactly the workflow and classifier test.

## Candidate publication and review

1. Freeze the local candidate and record revision/tree/path manifest, both feature-specific outputs, and the full mandatory RepoInfra output.
2. Commit, push, and create/update the single non-Draft candidate PR.
3. Prove local `HEAD`, remote branch OID, and PR `headRefOid` are identical.
4. Request independent exact-candidate AI Reviewer content review for that published SHA.
5. After PASS, re-prove the same three-way identity and hand that same SHA to PR Manager for required-check and merge supervision.
6. Keep explicit Owner approval for `.github/workflows/testflight.yml` as a separate pre-merge gate; AI review and CI cannot substitute.

No real release run or post-merge production evidence is a v3 completion condition.

## Preserved candidate reuse

For the existing registered Fullstack workspace, reuse is allowed only after Team Lead dispatch:

1. Re-read the issue metadata and verify the exact workdir, origin, branch, and current v2 base.
2. Prove the local diff is still exactly the workflow and classifier test.
3. Fetch the exact reviewed v3 planning revision.
4. Prove `73dd9ffd2f7cb1980cbe986d0ea9cd3442ecff85..v3` changes planning artifacts only.
5. Fast-forward the same branch/workspace to v3; do not reset, clean, create another checkout, copy changes, or resolve overlap silently.
6. Re-read status and prove the two local implementation paths are preserved.
7. If fast-forward or non-overlap proof fails, stop and return evidence to Team Lead recovery.
