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
- [x] CHK010 Missing/non-ancestor marker, ambiguous PR, malformed version, secret failure, post-upload failure, and tag failure are deterministic.

## Scope and feasibility

- [x] CHK011 Exact implementation files and explicit exclusions are present.
- [x] CHK012 All implementation paths map to RepoInfra and no AppUI/package change is implied.
- [x] CHK013 Verification commands have exact working directory/expected evidence and require full-output inspection.
- [x] CHK014 Real upload is excluded from planning/pre-merge verification and retained as post-merge evidence.

## Quality

- [x] CHK015 No placeholder, `NEEDS CLARIFICATION`, optional branch, or unstated product/authority choice remains.
- [x] CHK016 Requirements are traceable to slices/tasks and every task is schedulable or explicitly blocked.
- [x] CHK017 Constitution checks pass before and after design without exception.

## Notes

- Completion marks require a fresh read of the final artifacts, not author intent.
