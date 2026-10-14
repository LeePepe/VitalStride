# Requirements Checklist: TestFlight auto-release after verified main CI

**Purpose**: Validate specification completeness before plan/tasks review.

**Created**: 2026-10-15

**Feature**: [spec.md](../spec.md)

## Intent and authority

- [x] CHK001 Exact issue revision, Owner decision, target repository, and base SHA are recorded.
- [x] CHK002 Automatic release, bounded manual force, and post-merge evidence are stated as outcomes.
- [x] CHK003 `.github/**` explicit Owner approval is separate from AI review and CI.

## Behaviour contract

- [x] CHK004 Existing behaviour is evidence-based and names current trigger, markers, runner, versioning, signing, and tests.
- [x] CHK005 Compatibility preserves every unaffected signing/profile/telemetry/release behavior.
- [x] CHK006 Every removed behavior cites a Decision ID or Owner authority.
- [x] CHK007 No test deletion or unrelated assertion weakening is authorized.

## Acceptance and edge cases

- [x] CHK008 Every acceptance scenario has a stable `USx/ACy` identifier and objective evidence surface.
- [x] CHK009 Automatic source-event, exact-SHA, path, marker, force, version-label, concurrency, failure, and summary cases are covered.
- [x] CHK010 Missing/non-ancestor success marker, ambiguous automatic/manual PR, malformed version, secret failure, post-upload failure, durable attempt claim, and success-marker indeterminate/recovery states are explicit and fail closed.

## Scope and feasibility

- [x] CHK011 Exact implementation files and explicit exclusions are present.
- [x] CHK012 All implementation paths map to RepoInfra and no AppUI/package change is implied.
- [x] CHK013 Verification commands have exact working directory/expected evidence and require full-output inspection.
- [x] CHK014 Real upload is excluded from planning/pre-merge verification and retained as post-merge evidence.

## Quality

- [x] CHK015 No placeholder, `NEEDS CLARIFICATION`, optional branch, or unstated product/authority choice remains.
- [x] CHK016 Requirements are traceable to slices/tasks and every task is schedulable or explicitly blocked.
- [x] CHK017 Constitution checks pass before and after design without exception.
- [x] CHK018 Path classification is deterministic for NUL-safe records, exclusions, mixed diffs, deletion, and both rename/copy endpoints.
- [x] CHK019 Immutable per-SHA claims cover the A→B→A lifetime case and are never moved, deleted, rolled back, or bypassed by force.
- [x] CHK020 Success-marker mutation uses immutable pending/resolved recovery evidence, a captured prior OID lease/readback, authoritative next-run ref-name/target validation, exact-pair gate-only reconciliation, confirmed-unpaired Owner recovery, malformed/mismatched/orphan fail-closed behavior, four Owner recovery dispositions/transitions, and no retroactive success.
- [x] CHK021 Manual label policy, US1/AC5 task ownership, the five-row graph, and T005 success-only completion agree across every artifact.

## Notes

- Completion marks require a fresh read of the final artifacts, not author intent.
