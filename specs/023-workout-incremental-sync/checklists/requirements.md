# Specification Quality Checklist: HealthKit workout incremental sync

**Purpose**: Validate specification completeness before planning review
**Spec**: `specs/023-workout-incremental-sync/spec.md`
**Reviewed**: 2026-08-31

## Content Quality

- [x] The outcome is stated from the workout-list user's perspective.
- [x] The spec avoids compiler-level implementation snippets.
- [x] Actors, user value, non-goals, and assumptions are explicit.
- [x] Repository terminology matches `CONTEXT.md` and the HealthKitService layer context.

## Requirement Completeness

- [x] No `NEEDS CLARIFICATION` marker remains.
- [x] Requirements distinguish snapshot, anchored changes, explicit range, invalidation, concurrency, and privacy behavior.
- [x] Acceptance scenarios cover the reported A → empty-delta regression.
- [x] Acceptance scenarios cover add, update, delete, idempotency, deterministic ordering, range coverage, restart/invalidation, stale work, and anchor/cache acceptance interleaving.
- [x] The contract forbids checkpoint-first advancement and defines currentness for same-semantic supersession.
- [x] The direct service path cannot become an independent default-anchor writer outside cache acceptance.
- [x] Public compatibility, files in scope, files not to touch, and exact package verification are explicit.
- [x] The prepared-fetch capability is explicitly package-internal, adds no public witness requirement, and preserves snapshot-only fallback for existing public providers.
- [x] Cache acceptance follows the prepared result's semantic when anchored preparation falls back to a baseline.
- [x] Mutable request, transaction, waiter, and provider-lane state is actor-isolated with no unsafe Sendable or lock-owned helper escape.
- [x] Exactly-once remove-before-resume settlement defines owner, non-owner, failure, supersession, and invalidation outcomes.
- [x] Cancellation/invalidation drains active and queued provider-lane requests and permits a successor before stale provider completion.
- [x] The canonical cache-entry model contains an optional opaque cache-accepted candidate checkpoint: present only when an accepted prepared baseline/change supplies one; absent for nil-checkpoint prepared results, legacy fallback, and explicit-range snapshots.
- [x] `Workout Cache Entry` has one field set—records, coverage, provenance, optional accepted checkpoint; generation/key/request identity stay transaction-only and request order is not a contract field.
- [x] The cache publishes the candidate and synchronously invokes matching provider acceptance before caller success without treating the `Void` call as confirmed persistence.
- [x] Silent acceptance no-advance leaves durable state on the prior checkpoint and is covered by idempotent replay/resubmission rather than rollback or false success evidence.
- [x] The adversarial matrix distinguishes provider query completion from cache acceptance and proves c2 rejection, replay from c1, and later A+B/c2 acceptance.
- [x] The staged breakdown requires one public-cache test-first tracer at a time: mandatory RED→GREEN for missing/incorrect or changing behavior, characterization-GREEN only for already-correct unchanged paths, and no manufactured RED or timing-based synchronization.
- [x] Stage 0A makes Team Lead prove no pre-existing owner before dispatch; Stage 0B excludes only the expected Fullstack run and proves no competing owner before editing. Both pin clean `f5690f…` four-way equality, fingerprints, and fail-closed divergence without reset.
- [x] Stages A–E have explicit entry, eligible evidence mode, replacement/unchanged-path proof, regression, and exit evidence; mandatory RED is explicit for unsafe-Sendable/Mutex state, multiple completion, stranded continuation-holder lanes, previous/candidate mismatch, and checkpoint decoding/comparison, while verification-only Stage F has explicit entry, audit, package/diff/SHA proof, and exit evidence.
- [x] Removal/replacement mapping covers all repeated five-P1 source/test facts from comments `00966211…` and `9d352f6d…`.
- [x] Stage F rejects `f5690f…`, `d853728…`, empty/same-tree commits, unchanged mandatory file blobs, focused-only testing, stale patterns, routing errors, and SHA mismatches.
- [x] Only Fullstack may request review for a genuinely new local/tracking/remote/PR-equal SHA after full package/diff/pattern gates.
- [x] Success criteria are measurable without HealthKit hardware.

## Readiness Traceability

- [x] Every acceptance scenario maps to US1 in `tasks.md`.
- [x] US1 maps to layer-scoped T023-001 and T023-002.
- [x] Task dependencies are explicit and acyclic.
- [x] Each task names one owning layer, exact paths, exclusions, contract impact, local acceptance, and exact verification.
- [x] Constitution §I/II/III and Quality Bars A-D/I have been checked before and after design.

## Result

PASS — the specification is ready for independent planning review at a pinned revision.
