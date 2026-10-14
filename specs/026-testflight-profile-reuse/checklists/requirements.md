# Specification Quality Checklist: TestFlight in-run profile reuse

**Purpose**: Validate specification completeness before planning and independent review
**Spec**: `specs/026-testflight-profile-reuse/spec.md`
**Reviewed**: 2026-10-14

## Content Quality

- [x] Release operator and delivery owner outcomes are explicit.
- [x] The specification avoids implementation-level Ruby, YAML, and build-setting snippets.
- [x] Existing behaviour, compatibility, removed behaviour, non-goals, and assumptions are explicit.
- [x] Every removed behaviour cites a stable decision ID; no test deletion or weakening is authorized.
- [x] Repository terminology matches the AppUI and RepoInfra contexts.
- [x] The `VitalStride/CONTEXT.md` target exclusion is explicitly authorized as T001 baseline reconciliation; the support document's content remains out of scope.

## Requirement Completeness

- [x] No `NEEDS CLARIFICATION`, optional alternative, or unresolved product choice remains.
- [x] Stable IDs cover every functional requirement and acceptance scenario.
- [x] Acceptance distinguishes absent/nil and whitespace-only output from nonblank names containing leading/trailing/embedded whitespace; valid original values remain verbatim through archive and export.
- [x] Acceptance covers both app and widget, unusable output, target crossing, shell-safe values, unsigned builds, PR regression, and the Owner-consent gate.
- [x] Force behavior, manual Release signing, Automatic Debug signing, secret handling, workflow freshness, upload/distribution, and release-tag compatibility are preserved.
- [x] The real-upload evidence form is explicitly manual and cannot be substituted by static or unsigned checks.
- [x] Success criteria are measurable and distinguish implementation proof from Owner-controlled production proof.
- [x] T001 authorizes exactly three AppUI truth-source edits in `project.yml`: one baseline exclusion and two target-specific profile substitutions; generated project changes are synchronization evidence only.
- [x] T001 and T002 retain separate AppUI and RepoInfra implementation commits, and T003 requires frozen-tree review before unchanged publication.
- [x] Forward-only recovery preserves PR #441 until replacement publication, forbids force-push/history rewrite, and then requires PR Manager to close #441 with the replacement link.
- [x] MY-1675 / PR #442 must merge through its one-time exact-head human bootstrap before MY-1660 can satisfy its separate trusted-review shipping gate.
- [x] MY-1660 cannot reuse the #442 bypass; its replacement requires a fresh eligible post-fix `pull_request_target` event and a real schema-valid passing `codex-review-target` result for its current head.
- [x] The immutable `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` replacement source/ancestry base is explicitly distinct from the fresh event's trusted `github.event.pull_request.base.sha` on #442-fixed `main`.

## Readiness Traceability

- [x] Constitution Principle IV and Development Workflow plus Quality Bars A, E, I, and J are referenced by the planned acceptance surface.
- [x] The required DoR fields will be completed in `plan.md` and task metadata: exact scope, exclusions, interface impact, acceptance, commands, working directory, and dependencies.
- [x] The cross-layer handoff is defined as one two-value interface rather than duplicated signing rules.
- [x] No actual ASC call, Developer Portal mutation, signing operation, upload, or workflow dispatch is required for implementation review.
- [x] The newly authored regression has a fail-closed immutable-base overlay procedure that mechanically requires stable fixed-name and action-return-fallback assertion markers without reverting T001, followed by separate final-green commands.
- [x] The T001–T005 graph separates implementation, frozen-tree publication, T004 trusted-review shipping proof, and T005 Owner-controlled production proof; it models replacement publication and the independent #442-fixed event base as a T004 join without broadening implementation scope.

## Result

PASS — the specification is deterministic and ready for Plan-stage artifacts.
