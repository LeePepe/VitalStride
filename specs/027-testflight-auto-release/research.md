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

**Decision**: Diff `testflight/last-released..candidate` after fetching full history/tags and classify NUL-safe change records. Qualifying paths are narrow shipped package manifest/source/plugin families, shipped app source/resource/asset/configuration families, `project.yml`, `fastlane/Fastfile`, and `fastlane/Appfile`. Explicit documentation/context/test/generated/workflow/script exclusions apply per endpoint before positive matching. A relevant deletion qualifies; either relevant rename/copy endpoint qualifies; excluded-to-excluded does not; a mixed diff qualifies when any record does. Trigger-time GitHub `paths` is not used.

**Why**: `workflow_run` has no useful path filter and eligibility must accumulate app changes across skipped docs/spec/CI-only merges until a release succeeds.

**Rejected**:

- Compare only the merged PR: loses app changes accumulated behind a failed/skipped release.
- Treat any commit as eligible: releases docs/spec/test/CI-only changes.
- Include broad `Packages/**` or app roots: would incorrectly qualify package tests/contexts or future support files.
- Include `.github/**` or `scripts/**`: conflicts with the explicit skip-CI-only requirement.

## R3 — Same-SHA safety and no retry

**Decision**: Preserve moving `testflight/last-released` for success and create immutable `testflight/attempted/<SHA>` tags as pre-lane claims. Confirm the exact remote claim before any archive/upload. Once claimed, the same SHA is not retried, including manual force and after later SHAs have been claimed.

**Why**: A single moving attempt marker remembers only the latest SHA: after A fails and B advances it, A can re-enter. An immutable per-SHA claim preserves lifetime evidence. A marker written only after upload also cannot distinguish “upload succeeded, marker write failed” from “nothing uploaded,” so the pre-attempt claim closes that duplicate window and implements no retry/rollback.

**Rejected**:

- Success marker only: leaves the post-upload/tag-failure duplicate window.
- Moving `testflight/last-attempted`: loses older claims and fails the A→B→A case.
- Move success marker before upload: would call failed attempts released and lose the last successful baseline.
- Delete/rollback a claim on failure: violates no rollback and reopens duplicate ambiguity.

## R4 — Version seam

**Decision**: Read and validate one uniform project marketing version before the attempt. Resolve the exact merged PR/label for both automatic and manual current-main candidates; `release:minor` creates a per-run minor increment. Pass one resolved value into Fastlane, where archive and post-upload lookup reuse it. Keep the existing app-wide ASC maximum-plus-one build counter and emit the selected build number as safe output.

**Why**: Fastfile's hardcoded `1.1` duplicates `project.yml` and cannot express the label decision. Editing and committing project files from a release workflow would violate PR-required delivery and XcodeGen ownership.

**Rejected**:

- Commit a version bump from Actions: creates an unreviewed main write/loop.
- Keep hardcoded Fastfile version: drifts from project truth and ignores `release:minor`.
- Scope the build counter by marketing version or use GitHub run number: can reuse/lower an ASC-global build number and regresses the accepted fix.

## R5 — Fail-closed release phases

**Decision**: Candidate/marker/PR/version checks, immutable claim, signing, archive, upload, processing, internal distribution, dSYM publication, and success-marker update/confirmation are critical. Immediately before mutation, create and confirm immutable `testflight/success-pending/<SHA>`. Capture the confirmed prior success-marker OID, update only with that expected value as a compare-and-swap/lease, then freshly read the remote ref. Exact candidate readback is sealed by creating and confirming immutable `testflight/success-resolved/<SHA>` before reporting success. Every later authoritative preflight enumerates both namespaces, validates that each ref target equals the SHA encoded in its well-formed name, rejects malformed/mismatched/orphan refs, and fails before upload when a confirmed pending ref lacks its matching resolved ref. An exact valid pair clears only the recovery gate; it never converts the prior failed run into success evidence. Any failure terminates with phase/reason evidence and the attempt claim stays. Failures before pending creation preserve the prior marker; later failure leaves durable recovery evidence. A prior baseline, conflicting SHA, unreadable/unknown remote result, or ambiguous resolution confirmation records safe failure or `success-marker-indeterminate` and performs no automatic overwrite/rollback. An ambiguous resolution write fails its current run without asserting pair state; the next authoritative preflight either observes the exact valid pair and clears only the gate, confirms the resolved ref absent and requires Owner recovery, or fails closed on invalid namespace state before another candidate proceeds.

**Why**: Current rescue/`continue-on-error` behavior can report workflow success and move the marker after incomplete distribution or diagnostics. A remote mutation or resolution-ref creation can also succeed while confirmation becomes unavailable, so neither “every failure leaves the marker unchanged” nor “failed confirmation means the ref is absent” is representable. An ephemeral run result alone also cannot block a queued or future candidate. The immutable pending/resolved pair plus authoritative next-run namespace validation makes recovery state durable and machine-checkable while preserving the Owner's fail-closed, no-retry, and no-rollback requirements without inventing remote state or retroactively reclassifying a failed run.

**Owner recovery dispositions**:

- Remote equals candidate: reconcile the successful marker and uploaded build without re-uploading the claimed SHA, then create/confirm the matching immutable resolved ref.
- Remote equals captured prior baseline: verify App Store Connect evidence; Owner may authorize a leased forward advance and confirmation, then create/confirm the matching immutable resolved ref, never a re-upload.
- Remote equals another SHA: do not overwrite automatically; reconcile release ordering/supersession and create/confirm the matching immutable resolved ref only after that disposition is safely recorded.
- Remote is unreadable/invalid: perform no mutation or resolution write; leave the pending ref unpaired and remain blocked.

Pending and resolved refs are never moved or deleted. Automatic execution creates a resolved ref only after exact candidate readback; exceptional resolution authority remains with the Owner. If automatic resolution confirmation is ambiguous, that run remains failed; a later exact valid pair reconciles only the preflight gate, while confirmed absence retains the Owner-recovery requirement.

**Narrow compatibility**: TEMP-PRELAUNCH remains a warning-only internal-TestFlight audit because its accepted policy explicitly distinguishes internal testing from the App Store submission gate.

## R6 — Approval and permission boundary

**Decision**: Limit implementation to one `.github` workflow plus Fastfile and its existing regression module. Require explicit Owner approval before merge and use only least privilege needed for tags and exact merged-PR label reads.

**Why**: No tracked CODEOWNERS or active code-owner review rule enforces `.github/**` approval on this base. The issue's Owner decision remains a separate authority gate from AI content review and CI.

**Rejected**:

- Add CODEOWNERS/ruleset changes: outside scope and creates a second governance goal.
- Treat AI Reviewer PASS as Owner approval: conflates independent content review with explicit protected-path authority.

## R7 — Verification boundary

**Decision**: Use credential-free contract tests (including narrow path precedence, A→B→A durable claims, shared automatic/manual label policy, pending/resolved recovery lockout, and success-marker ambiguity), Fastfile syntax, the complete RepoInfra gate, static diff/traceability inspection, and one post-merge operational evidence record. No TestFlight upload occurs during planning or pre-merge verification.

**Baseline note**: The focused test has 10/10 passing cases. The full RepoInfra script printed one failure and one error under the local Xcode Python 3.9 toolchain despite exit 0; future claims must inspect the full summary and route environment failures instead of relying on exit status.
