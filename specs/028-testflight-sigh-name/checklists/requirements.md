# Specification Quality Checklist: TestFlight per-call SIGH_NAME capture

**Purpose**: Validate requirement completeness before independent planning review
**Created**: 2026-10-15
**Feature**: `specs/028-testflight-sigh-name/spec.md`

## Content Quality

- [x] No implementation code is embedded in the specification
- [x] Requirements focus on observable behavior and contract boundaries
- [x] All mandatory sections are complete
- [x] Existing behavior, compatibility, and removed behavior are explicit

## Requirement Completeness

- [x] No `NEEDS CLARIFICATION` marker remains
- [x] Every requirement is testable and carries a stable identifier
- [x] Acceptance scenarios cover normal, failure, overwrite, shell-safety, and operational outcomes
- [x] Production neutralizes both stale-capable name locations before every real provisioning call and captures immediately afterward
- [x] Separate stale-seeded real-action cases prove target-specific missing-app and missing-widget failure
- [x] Scope and exclusions are bounded to one RepoInfra goal and the two writable paths required after merged T001 base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`
- [x] Dependencies and assumptions are identified

## Repository and Workflow Alignment

- [x] Constitution and `RepoInfra/CONTEXT.md` constraints are referenced
- [x] Incorrect `026` authority is explicitly superseded without rewriting history
- [x] `027` workflow/classifier behavior is explicitly preserved
- [x] Real Fastlane/Sigh action coverage is mandatory and cannot be stubbed away
- [x] Every implementation task owns one layer and exact paths
- [x] Every task has runnable verification and dependency edges
- [x] Post-merge TestFlight evidence is separated from credential-free implementation verification
- [x] Owner-delegated Option A is recorded: qualifying automatic exact-head evidence is authoritative, manual `force=false` is supplemental, and duplicate/forced upload is forbidden
- [x] Focused and mandatory gate execution share one canonical resolve-actual-fastlane contract: unchanged-PATH command, actual selected/provided RubyGems toolchain, CLI/gem/loaded-library/source agreement, minimum 2.238.0, and fail-closed behavior without installs, PATH workarounds, packaging assumptions, alternate runtimes, skips, hook bypass, or workflow edits
- [x] T001 is reconciled as the merged read-only production/coverage baseline; T002 owns exactly the fixture resolver adaptation and mandatory gate wiring; T003 owns no source repair and verifies the exact two-path candidate

## Readiness

- [x] `spec.md`, `plan.md`, `research.md`, `data-model.md`, contract, quickstart, and `tasks.md` agree
- [x] Acceptance traceability covers every US/AC, FR, RB (including RB-006), and SC identifier
- [x] Open risks and the Planner-machine Python baseline limitation are documented
- [x] Package is ready for exact-revision AI Reviewer spec/plan gate
- [x] Round 1 stale-state and nondeterministic-T004 blockers remain resolved; the later resolve-actual-fastlane decision supersedes only the exact-2.238.0 acceptance from reviewed revision `7c5fc64430c2b8dbf6c4216cf7e3203790c45821`
