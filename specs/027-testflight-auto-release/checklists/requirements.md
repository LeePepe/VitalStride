# Requirements Checklist: Minimal automatic TestFlight release

**Purpose**: validate v3 specification completeness before independent exact-revision review.
**Created**: 2026-10-15
**Feature**: [spec.md](../spec.md)

## Authority and scope

- [x] CHK001 Product base, v2 predecessor, Lead direction, and Team Lead handoff are recorded.
- [x] CHK002 v3 is limited to successful-main automatic orchestration, accumulated relevance, existing lane invocation, and post-upload sole-marker advance.
- [x] CHK003 The three-path ownership ceiling and expected two-path patch are explicit.
- [x] CHK004 Explicit Owner approval for `.github/workflows/testflight.yml` remains separate from AI review and CI.

## Existing, compatible, and removed behaviour

- [x] CHK005 Existing manual workflow, marker, runner/group, lane, regression surface, and signing/secret boundary are evidence-based.
- [x] CHK006 Existing Fastlane build/upload, signing, version/build, telemetry, runner, and safe-log behaviour are compatibility surfaces, not new shadow-test requirements.
- [x] CHK007 Removed v2 planning behavior is distinguished from unchanged product-base behavior and cites current authority.
- [x] CHK008 Candidate-PR/version, bounded manual force, bootstrap/relation/readback expansion, recovery/CAS state, broad shadow suites, and production evidence are absent from active requirements.

## Automatic contract

- [x] CHK009 Exact successful `CI` / `push` / `main` source and immutable `workflow_run.head_sha` reuse are objective.
- [x] CHK010 Relevance is literally `git diff testflight/last-released..head_sha`; invalid marker fails closed.
- [x] CHK011 App predicates are identical between spec and contract, including root-only app entitlement families and all four fully prefixed `VitalStrideWidgets/**` families.
- [x] CHK012 NUL-safe mixed, deletion, rename/copy endpoint, exclusion precedence, accumulated irrelevant-range cases, and one nested-entitlement negative per app root are testable.
- [x] CHK013 Existing lane invocation precedes the sole marker update; pre-marker failure leaves it unchanged; no automatic retry/rollback exists.
- [x] CHK014 One app group, non-cancellation, job-level `contents: write`, and no broader permission are explicit.
- [x] CHK015 No per-SHA, second-marker, queue, cursor, CAS/lease, journal, pending/resolved, or recovery state is authorized.

## Verification and delivery

- [x] CHK016 Feature-specific verification is exactly classifier unit tests plus `actionlint` workflow lint; the separate mandatory `bash scripts/test-repoinfra.sh` repository gate remains unchanged.
- [x] CHK017 `actionlint` is identified as an executor prerequisite because the pinned repository has no native workflow linter.
- [x] CHK018 Full mandatory RepoInfra output is required; standalone Ruby, XcodeGen/xcodebuild/SwiftPM, Fastlane execution, upload/tag mutation, production evidence, and feature-specific shadow-policy suites are explicitly excluded.
- [x] CHK019 Every active US/AC, FR, RB, and SC identifier has semantic task traceability.
- [x] CHK020 The task graph is exactly T001 implementation → T002 freeze/check → publish one non-Draft PR → three-way SHA proof → exact review → post-PASS SHA re-proof → PR Manager.
- [x] CHK021 Child reconciliation keeps two rows and supersedes three only after planning PASS, without starting implementation.
- [x] CHK022 Preserved candidate reuse is same-workspace fast-forward with identity/non-overlap proof and a fail-closed recovery path.

## Notes

Completion marks reflect a fresh read of all eight v3 artifacts. Any content change requires this checklist to be read again before requesting review.
