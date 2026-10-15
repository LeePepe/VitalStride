# Implementation Plan: TestFlight per-call SIGH_NAME capture

**Planning version**: MY-1815/v1
**Branch**: `028-testflight-sigh-name`
**Date**: 2026-10-15
**Spec**: `specs/028-testflight-sigh-name/spec.md`
**Product base**: `663054cb4e7f58459fd0caf6a0710f6e74f18bd0`
**Layer**: `RepoInfra` (`depends_on: []`)

## Summary

Keep the existing two target-specific profile fetches and signing interface. Immediately before each real fetch, neutralize both `ENV["SIGH_NAME"]` and lane-context `SharedValues::SIGH_NAME`; immediately after that fetch, capture only its newly published lane-context value. Retain all missing/blank/equal pre-archive guards with target-specific failures, and reuse the captured values unchanged for shell-safe archive input and export mapping.

Add a real-action Ruby regression modeled on VoxPocket PR #100: load Fastlane/Sigh, load the repository Fastfile, invoke the real provisioning action, and replace only `Sigh::Manager.start` plus credential/build/upload boundaries. Wire that test into the existing RepoInfra gate without changing CI or TestFlight workflows.

## Technical Context

| Item | Decision |
|---|---|
| Runtime | Homebrew formula Ruby + Fastlane 2.238.0 (required CI) or 2.241.0 (release host), dynamically resolved; existing Bash RepoInfra gate |
| Supported profile-name output | `lane_context[SharedValues::SIGH_NAME]` |
| Action return | UUID; explicitly not a display-name source |
| State lifetime | Environment and lane-context names are independently stale-capable; real action conditionally republishes lane context; neutralize both before every call, then capture immediately |
| Testing | Minitest with real Fastlane/Sigh action; external Sigh manager/build/upload boundaries replaced; stale-seeded missing-app and missing-widget cases |
| Repository gate | `bash scripts/test-repoinfra.sh` |
| Layer | Dependency-free `RepoInfra` |
| External mutation | Forbidden during planning and implementation verification |

## Evidence Baseline

- Local planner checkout, `origin/main`, and product base are all `663054cb4e7f58459fd0caf6a0710f6e74f18bd0` before planning edits.
- `fastlane/Fastfile` fetches app then widget with `force: true` and `skip_install: false`, then reads two nonexistent target-derived environment keys after both calls.
- The failed run is GitHub Actions run `38690610783`; it stops at the app missing-name guard before archive.
- Fastlane 2.241.0 source `get_provisioning_profile.rb` defines `SharedValues::SIGH_NAME`, copies `ENV["SIGH_NAME"]` into lane context, and returns the UUID.
- The same action contract is present on the required CI runner's Fastlane 2.238.0. The action assigns lane context only when `ENV["SIGH_NAME"]` is present; Sigh and the action do not clear a prior environment or lane-context name when a call publishes no name.
- Repository-wide inspection found exactly two fabricated production reads, both in `fastlane/Fastfile`; scripts contain no additional production read.
- App/widget custom specifier inputs and export reuse already exist and remain correct.
- VoxPocket PR #100 provides the accepted real-action fixture shape: require real Fastlane/Sigh, clear/restore lane context, replace `Sigh::Manager.start`, publish distinct name/UUID fixtures, and execute the real action through the actual lane.
- `scripts/test-repoinfra.sh` is the existing PR-time RepoInfra entrypoint and currently discovers Python tests only.
- Required CI runs `bash scripts/test-repoinfra.sh` on `macos-26` with Homebrew Fastlane 2.238.0; the release host provides Homebrew Fastlane 2.241.0. The focused test and mandatory gate must use the same runtime-discovery contract without changing either workflow.
- Planner-machine `bash scripts/test-repoinfra.sh` has unrelated Python 3.9 baseline failures (`X | None` import and unavailable `tomllib`); this does not weaken the required green implementation gate on the supported executor.

## Constitution Check

### Before design

- **Principles I–VII**: PASS. No health data, Swift, package, XcodeGen, AI, localization, or platform feature changes.
- **Quality Bar A**: PASS. One dependency-free RepoInfra slice owns three exact paths; all workflow/project/product surfaces are excluded.
- **Quality Bar D**: PASS. Existing release failure uses the established Fastlane error path; no new production force-cast/try/fatal behavior.
- **Quality Bar I**: PASS. The defect receives credential-free real-action coverage and no test is removed or weakened.
- **Quality Bar J**: PASS. AI Reviewer owns content review; PR Manager owns published CI/shipping state; Team Lead owns post-merge operational outcome.
- **Development Workflow / ADR-0021**: PASS. Planner publishes only Spec Kit artifacts. Fullstack freezes the local candidate for prepublication content review under the scoped VitalStride contract, then publishes only the permitted tree.

### After design

- Dependency graph is acyclic: lane repair plus its real-action fixture precede mandatory gate wiring; delivery verification depends on both; post-merge production validation depends on reviewed merge.
- The hard fail-closed invariant is enforced by neutralizing both stale-capable name locations before every real call, capturing immediately afterward, and validating before `build_app`. The actual-lane fixture separately pre-seeds both locations for missing app and missing widget output and proves the matching target-specific failure.
- The must-not-fabricate invariant is enforced by real `GetProvisioningProfileAction` execution plus a source prohibition test for the target-derived convention.
- The per-call invariant is enforced by distinct sequential fixtures and proof that the second action overwrites lane context while the already captured app variable remains correct.
- No constitution, ADR, domain term, layer contract, public interface, or dependency change is required.

## Project Structure

### Planning artifacts

```text
specs/028-testflight-sigh-name/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/requirements.md
├── contracts/profile-name-handoff.md
└── tasks.md
```

### Implementation paths

```text
fastlane/Fastfile
scripts/test-repoinfra.sh
scripts/tests/test_testflight_packaging.rb
```

**Structure Decision**: All implementation paths belong to RepoInfra. The new Ruby test is separate from `test_testflight_freshness.py` so `027`'s classifier suite remains unchanged. The existing RepoInfra entrypoint receives only the minimum mandatory Ruby-test invocation.

## Files in Scope

- `fastlane/Fastfile`
- `scripts/tests/test_testflight_packaging.rb` — new real-action regression
- `scripts/test-repoinfra.sh` — minimal discovery/invocation only

## Files NOT to Touch

- `.github/workflows/**`, including `testflight.yml` and `ci.yml`
- `project.yml` and `VitalStride.xcodeproj/**`
- `scripts/tests/test_testflight_freshness.py` and every other existing test
- Other scripts, hooks, rulesets, review policy, and security configuration
- `VitalStride/**`, `VitalStrideMac/**`, `VitalStrideWatch Watch App/**`, `VitalStrideWidgets/**`, all app tests, `Packages/**`, and `Prototype/**`
- Entitlements, bundle identifiers, team/certificate/profile resources, secrets, keychains, `.p8`, `.mobileprovision`, logs, and build artifacts
- Existing specs, ADRs, contexts, and constitution outside this new planning directory

## Interface Contract

### Public signatures

No public product, Swift, workflow-input, persistence, or external API change.

### Internal profile handoff

| Fetch boundary | Required captured source | Archive consumer | Export consumer |
|---|---|---|---|
| app fetch | both stale name locations neutralized immediately before the call; current `SharedValues::SIGH_NAME` captured immediately after and before widget work | `VITALSTRIDE_APP_PROFILE_SPECIFIER` | `com.leepepe.vitalstride` |
| widget fetch | both stale name locations neutralized immediately before the call; current `SharedValues::SIGH_NAME` captured immediately after | `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` | `com.leepepe.vitalstride.widgets` |

- Captured values are non-empty, target-distinct, and opaque.
- Missing/blank current-call output or equal captured values stop before `build_app`; missing output identifies the matching target and cannot reuse stale environment/lane state.
- UUID return values and fabricated target-derived env keys are forbidden name sources.
- Archive and export consume the same target-specific captured variable.

## Test Contract

The Ruby fixture must:

1. dynamically resolve `brew --prefix fastlane` and `brew --prefix ruby`, run with the formula Ruby and Fastlane formula `libexec` on `GEM_PATH`, and require the installed real `fastlane`, `sigh`, and `sigh/manager` libraries without ambient `/usr/bin/ruby` or hard-coded architecture prefixes;
2. load the repository Fastfile rather than duplicating its profile logic;
3. snapshot and restore outer lane-context and Sigh environment state around each case, while preserving deliberate stale seeds inside each negative case until production performs its own pre-call neutralization;
4. replace only `Sigh::Manager.start` for profile/network installation and replace unrelated credential/build/upload external work;
5. invoke the real provisioning action twice with distinct target names and UUIDs and prove production neutralizes both stale name locations before each call;
6. separately pre-seed both locations for a missing app output and a missing widget output; require app-specific failure before widget/build work in the first case and widget-specific failure after preservation of the valid local app capture but before build work in the second;
7. prove scalar `SIGH_NAME` overwrite, immediate per-call capture, UUID non-use, blank/equal fail-closed behavior, shell-safe archive inputs, and matching export variables;
8. fail if production files use the fabricated target-derived environment-key convention;
9. make no network, credential, signing, upload, distribution, marker, or Developer Portal mutation.

`scripts/test-repoinfra.sh` must invoke the fixture exactly once through the same dynamically resolved formula-Ruby/Fastlane runtime used by the focused check. Missing Homebrew, formula Ruby, Fastlane `libexec`, or real libraries is a gate failure, not a skip or install request. No `.github/**` edit is permitted.

## Dependency Strategy

```text
T001 RepoInfra red fixture + per-call capture repair
  -> T002 mandatory RepoInfra gate wiring
       -> T003 freeze, verify, exact content review, unchanged publication, PR Manager handoff
            -> PR Manager merge with Owner gate
                 -> T004 Team Lead qualifying automatic TestFlight outcome proof on main
```

- T001 owns the Fastfile and focused fixture; T002 owns only mandatory test-entry wiring. Both are dependency-free RepoInfra tasks within one goal and one PR.
- T003 changes no source; findings return to T001 or T002 and any content change requires a new candidate review.
- T004 changes no repository file and belongs to Team Lead after merge. It observes the automatic `workflow_run` for successful CI on the exact merged head; it does not dispatch a release.

## Verification Strategy

Run from the repository root in the registered delivery checkout.

1. Real-action regression on either declared supported executor:
   `GEM_PATH="$(brew --prefix fastlane)/libexec" "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb`
2. Fastfile syntax:
   `ruby -c fastlane/Fastfile`
3. Full RepoInfra gate:
   `bash scripts/test-repoinfra.sh`
4. Candidate hygiene:
   `git diff --check`
5. Scope proof: changed implementation paths are exactly the three Files in Scope; every Files NOT to Touch path has zero diff.

The command dynamically resolves the active Homebrew prefixes and is valid for both the CI Fastlane 2.238.0 and release-host Fastlane 2.241.0 contracts; no `/opt/homebrew`, `/usr/local`, or ambient `/usr/bin/ruby` assumption is allowed. `scripts/test-repoinfra.sh` must use that same resolver/invocation, making the complete gate the portable canonical entrypoint. The real-action regression must be red-capable: it fails at the product base's fabricated/delayed reads and when stale values mask either missing target output, and passes only with pre-call two-source neutralization plus immediate per-call capture. The full RepoInfra gate remains mandatory even where the planner machine's unsupported Python baseline cannot supply a green local result.

### Forbidden before reviewed merge

- `fastlane ios beta`
- Any dispatch of `.github/workflows/testflight.yml`
- Any App Store Connect upload, signing, profile generation outside the stubbed fixture, Developer Portal mutation, distribution, or release-marker mutation

### Post-merge operational evidence

After PR Manager reports merge, Team Lead observes the unchanged automatic TestFlight `workflow_run` produced by successful CI on the exact merged `main` SHA. Authoritative evidence is the Actions run URL, `automatic-ci` source, `workflow_run.head_sha`/gate candidate/run head matching the merged SHA, terminal conclusion, marker/result state, and uploaded build number. No release is dispatched for T004 and no secret or signing artifact is attached. A manual `force=false` run is supplemental only after the automatic run is terminal and its marker covers that exact SHA; `force=true` and any duplicate upload are forbidden, and manual evidence cannot replace a missing or failed automatic proof.

## Complexity Tracking

No constitutional exception, new layer, new package, new workflow, new release state, or ADR is required. Real Fastlane/Sigh is an existing release dependency now exercised by the repository test gate, not a new product dependency.
