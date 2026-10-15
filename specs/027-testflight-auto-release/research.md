# Research: Minimal automatic TestFlight release after main CI

**Planning version**: v3
**Exact product base**: `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`
**Authority**: Lead direction `01a13cc2-e475-758b-b825-a9f622ca117a`; Team Lead handoff `01a13cc7-9937-74fb-bdc7-4f9a10aaa98d`

## R1 — Verified source and immutable candidate

**Decision**: consume completed workflow `CI` through `workflow_run`; accept only conclusion `success`, source event `push`, and head branch `main`. Capture and reuse `workflow_run.head_sha`.

**Evidence**: the base CI workflow is named `CI` and runs for pushes to `main`. The current TestFlight workflow checks out moving `main`, which is not the verified upstream candidate.

**Rejected**: direct `push` trigger; moving-main checkout; a branch-name-only or success-only guard.

## R2 — Literal accumulated range

**Decision**: fetch history/tags, resolve `testflight/last-released` as an ancestor commit, and classify NUL-safe records in `testflight/last-released..candidate` against the accepted app predicates. An irrelevant range skips and leaves the marker unchanged, so a later candidate naturally includes it.

**Evidence**: `workflow_run` has no usable repository path filter for this contract. The existing moving marker already defines the last successful release point.

**Rejected**: per-event changed files; exact candidate's merged PR; broad `Packages/**`; empty-tree bootstrap; a second cursor/skip marker. Missing, invalid, or non-ancestor marker state fails closed.

## R3 — Existing release lane and sole marker

**Decision**: keep `fastlane ios beta` unchanged as the build/upload lane. After it succeeds, move the sole `testflight/last-released` marker to the captured candidate. Any earlier failure reaches no marker-update command.

**Evidence**: the base workflow already calls the lane and then moves the marker. The Fastfile already generates, signs, builds, and uploads. No Fastfile redesign is needed.

**Rejected**: second release lane; Fastfile version/signing/distribution redesign; pre-upload marker movement; auxiliary success/attempt state.

## R4 — Failure semantics

**Decision**: add no automatic retry or rollback. A failure before marker update leaves the marker unchanged. Add no per-SHA record, queue, cursor, CAS/lease, journal, pending/resolved state, or recovery ref.

**Why**: the accepted minimal contract intentionally uses a single marker and GitHub's one non-cancelling app group. It does not model transactional recovery or guarantee durable FIFO processing.

**Rejected**: every heavier v1/v2 recovery or attempt model.

## R5 — Permission, concurrency, and approval

**Decision**: declare `contents: write` at the release job, retain one app-scoped concurrency group with `cancel-in-progress: false`, and add no broader permission. Keep explicit Owner approval for `.github/workflows/testflight.yml`.

**Evidence**: the base already has one non-cancelling group but declares write permission at workflow scope. No tracked enforcement can substitute for the explicit Owner boundary.

**Rejected**: workflow-wide write permission; multiple groups/custom queue; AI Reviewer PASS or CI as Owner approval; CODEOWNERS/ruleset expansion.

## R6 — Verification boundary

**Decision**: run only the classifier unit test and semantic workflow lint as feature-specific checks:

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
actionlint .github/workflows/testflight.yml
```

The classifier module is trimmed to the v3 contract. `actionlint` is an executor prerequisite because the pinned repository contains no native workflow linter.

The repository's mandatory layer gate remains separate and unchanged: `bash scripts/test-repoinfra.sh`. Its full output must report zero failures/errors; its exit code alone is insufficient. It supplements the feature checks and is not a workflow linter or v2 shadow-policy acceptance suite.

**Rejected as feature-specific gates**: standalone Ruby/Fastfile syntax, XcodeGen/xcodebuild/SwiftPM, Fastlane execution, upload/tag mutation, production evidence, and signing/profile/version/telemetry shadow-policy suites. The mandatory RepoInfra repository gate is not rejected or waived.

## R7 — Scope and preserved candidate

**Decision**: retain the three-path ownership ceiling but expect a two-path patch. Keep `fastlane/Fastfile` unchanged. Publish v3 as a planning-only descendant of the reviewed v2 revision so the preserved local implementation candidate can later be fast-forwarded in place after identity and non-overlap checks.

**Rejected**: a sibling planning commit that prevents fast-forward reuse; new checkout; reset/clean/stash-copy migration; silent conflict resolution; any fourth implementation path.
