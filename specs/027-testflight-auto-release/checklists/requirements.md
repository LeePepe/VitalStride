# Requirements Checklist: TestFlight auto-release after verified main CI

**Purpose**: Validate specification completeness before plan/tasks review.

**Created**: 2026-10-15

**Feature**: [spec.md](../spec.md)

## Intent and authority

- [x] CHK001 Exact issue revision, Owner decisions, target repository, and product base SHA are recorded.
- [x] CHK002 Automatic release, bounded manual force, and post-merge success evidence are stated as outcomes.
- [x] CHK003 `.github/**` explicit Owner approval is separate from AI review and CI.

## Behaviour contract

- [x] CHK004 Existing behaviour is evidence-based and names the current trigger, sole marker, runner/concurrency, versioning, signing, and tests.
- [x] CHK005 Compatibility preserves every unaffected signing/profile/telemetry/release behaviour and the single existing marker.
- [x] CHK006 Every removed behaviour cites a Decision ID or Owner authority, and superseded v1 planning is distinguished from product-base behaviour.
- [x] CHK007 No test deletion or unrelated assertion weakening is authorized.

## Acceptance and edge cases

- [x] CHK008 Every acceptance scenario has a stable `USx/ACy` identifier and objective evidence surface.
- [x] CHK009 Automatic source/event, exact SHA, accumulated path, marker relation, force, version label, concurrency, failure, and summary cases are covered.
- [x] CHK010 Missing/equal/ahead/ancestor/divergent marker, ambiguous automatic/manual candidate PR, malformed version, secret failure, critical-phase failure, and final marker update/readback failure are explicit and fail closed where required.

## Scope and feasibility

- [x] CHK011 Exact three implementation files and explicit exclusions are present.
- [x] CHK012 All implementation paths map to dependency-free RepoInfra and no AppUI/package/product change is implied.
- [x] CHK013 Verification commands have an exact working directory/evidence contract and require full-output inspection.
- [x] CHK014 Real upload and tag mutation are excluded from planning/pre-merge verification and retained as post-merge evidence.

## Quality

- [x] CHK015 No placeholder, `NEEDS CLARIFICATION`, optional branch, or unstated product/authority choice remains.
- [x] CHK016 Requirements trace to vertical slices/tasks, and every task is schedulable or explicitly blocked.
- [x] CHK017 Constitution checks pass before and after design without exception.
- [x] CHK018 Path classification is deterministic for NUL-safe records, exclusions, mixed diffs, deletion, and both rename/copy endpoints.
- [x] CHK019 The sole-marker model covers irrelevant→relevant and failure→later-candidate accumulation, same/already-covered protection, and explicitly excludes durable per-SHA attempt/skip state.
- [x] CHK020 Final marker mutation follows every earlier critical phase; exact readback alone is terminal success; update/readback ambiguity creates no auxiliary state or unobservable-state claim; the next invocation re-reads the remote marker; no automatic retry/rollback exists.
- [x] CHK021 Manual label policy, US1/AC5 task ownership, the five-row graph, and T005 success-only completion agree across every artifact.

## Notes

- Completion marks require a fresh read of the final artifacts, not author intent.
