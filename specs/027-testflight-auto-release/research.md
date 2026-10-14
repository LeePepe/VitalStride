# Research: TestFlight auto-release after verified main CI

**Exact base**: `a6e31c6f44797fd95ebe50b96fe2310a3e52d789`

## R1 — Trigger and candidate identity

**Decision**: Consume completed workflow `CI` through `workflow_run`; accept only successful `push` runs whose head branch is `main`; bind every subsequent decision to `workflow_run.head_sha`.

**Why**: A direct `push` trigger would prove only that a merge happened, not that the required CI run for that exact SHA passed. Checking out `main` after an event can release a later unverified SHA.

**Rejected**:

- `push: main` plus a later check lookup: duplicates CI orchestration and has race/permission complexity.
- `workflow_run` name/conclusion alone: `CI` also runs for PR and manual events, so event and branch guards are required.
- checkout of moving `main`: violates exact-revision safety.

## R2 — Accumulated app relevance

**Decision**: Diff `testflight/last-released..candidate` after fetching full history/tags. Qualifying paths are shipped app/package roots, `project.yml`, `fastlane/Fastfile`, and `fastlane/Appfile`. Trigger-time GitHub `paths` is not used.

**Why**: `workflow_run` has no useful path filter and eligibility must accumulate app changes across skipped docs/spec/CI-only merges until a release succeeds.

**Rejected**:

- Compare only the merged PR: loses app changes accumulated behind a failed/skipped release.
- Treat any commit as eligible: releases docs/spec/test/CI-only changes.
- Include `.github/**` or `scripts/**`: conflicts with the explicit skip-CI-only requirement.

## R3 — Same-SHA safety and no retry

**Decision**: Preserve `testflight/last-released` for success and add `testflight/last-attempted` as a pre-lane claim. Confirm the claim write before any archive/upload. Once claimed, the same SHA is not retried, including manual force.

**Why**: A single marker written after upload cannot distinguish “upload succeeded, marker write failed” from “nothing uploaded,” so a later run can duplicate the SHA. A durable pre-attempt claim closes that failure window and implements no retry/rollback.

**Rejected**:

- Success marker only: leaves the post-upload/tag-failure duplicate window.
- Move success marker before upload: would call failed attempts released and lose the last successful baseline.
- Delete/rollback a claim on failure: violates no rollback and reopens duplicate ambiguity.

## R4 — Version seam

**Decision**: Read and validate one uniform project marketing version before the attempt. Resolve the exact merged PR/label for automatic runs; `release:minor` creates a per-run minor increment. Pass one resolved value into Fastlane, where archive and post-upload lookup reuse it. Keep the existing app-wide ASC maximum-plus-one build counter and emit the selected build number as safe output.

**Why**: Fastfile's hardcoded `1.1` duplicates `project.yml` and cannot express the label decision. Editing and committing project files from a release workflow would violate PR-required delivery and XcodeGen ownership.

**Rejected**:

- Commit a version bump from Actions: creates an unreviewed main write/loop.
- Keep hardcoded Fastfile version: drifts from project truth and ignores `release:minor`.
- Scope the build counter by marketing version or use GitHub run number: can reuse/lower an ASC-global build number and regresses the accepted fix.

## R5 — Fail-closed release phases

**Decision**: Candidate/marker/PR/version checks, claim, signing, archive, upload, processing, internal distribution, dSYM publication, and success-marker update are critical. Any failure terminates with phase/reason evidence; the claim stays and the success marker does not move.

**Why**: Current rescue/`continue-on-error` behavior can report workflow success and move the marker after incomplete distribution or diagnostics. The Owner required fail closed, no retry, and no rollback.

**Narrow compatibility**: TEMP-PRELAUNCH remains a warning-only internal-TestFlight audit because its accepted policy explicitly distinguishes internal testing from the App Store submission gate.

## R6 — Approval and permission boundary

**Decision**: Limit implementation to one `.github` workflow plus Fastfile and its existing regression module. Require explicit Owner approval before merge and use only least privilege needed for tags and exact merged-PR label reads.

**Why**: No tracked CODEOWNERS or active code-owner review rule enforces `.github/**` approval on this base. The issue's Owner decision remains a separate authority gate from AI content review and CI.

**Rejected**:

- Add CODEOWNERS/ruleset changes: outside scope and creates a second governance goal.
- Treat AI Reviewer PASS as Owner approval: conflates independent content review with explicit protected-path authority.

## R7 — Verification boundary

**Decision**: Use credential-free contract tests, Fastfile syntax, the complete RepoInfra gate, static diff/traceability inspection, and one post-merge operational evidence record. No TestFlight upload occurs during planning or pre-merge verification.

**Baseline note**: The focused test has 10/10 passing cases. The full RepoInfra script printed one failure and one error under the local Xcode Python 3.9 toolchain despite exit 0; future claims must inspect the full summary and route environment failures instead of relying on exit status.
