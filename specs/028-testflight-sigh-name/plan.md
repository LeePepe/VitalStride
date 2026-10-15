# Implementation Plan: TestFlight per-call SIGH_NAME capture

**Planning version**: MY-1815/v1
**Branch**: `028-testflight-sigh-name`
**Date**: 2026-10-15
**Spec**: `specs/028-testflight-sigh-name/spec.md`
**Implementation base**: `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`
**Planning lineage**: supersedes reviewed revision `7c5fc64430c2b8dbf6c4216cf7e3203790c45821`
**Layer**: `RepoInfra` (`depends_on: []`)

## Summary

Use the merged T001 implementation at `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8` as the read-only production baseline: it keeps the two target-specific fetches, neutralizes both stale name locations before each call, captures immediately afterward, and retains all pre-archive guards and archive/export mapping.

Revise only the merged Ruby fixture's executor bootstrap so it resolves Fastlane from unchanged `PATH`, uses that command's actual RubyGems toolchain, proves CLI/gem/loaded-library/source agreement on one version at or above 2.238.0, and fails closed for missing or incoherent tooling. Preserve every real-action and behavioral case, then wire the same canonical fixture exactly once into the existing RepoInfra gate without changing the Fastfile, CI, or TestFlight workflows.

## Technical Context

| Item | Decision |
|---|---|
| Runtime | Actual Fastlane toolchain selected/provided by the `fastlane` command resolved from unchanged `PATH`; CLI/gem/loaded-library/source agreement; documented minimum 2.238.0; existing Bash RepoInfra gate |
| Supported profile-name output | `lane_context[SharedValues::SIGH_NAME]` |
| Action return | UUID; explicitly not a display-name source |
| State lifetime | Environment and lane-context names are independently stale-capable; real action conditionally republishes lane context; neutralize both before every call, then capture immediately |
| Testing | Minitest with real Fastlane/Sigh action; external Sigh manager/build/upload boundaries replaced; stale-seeded missing-app and missing-widget cases |
| Repository gate | `bash scripts/test-repoinfra.sh` |
| Layer | Dependency-free `RepoInfra` |
| External mutation | Forbidden during planning and implementation verification |

## Evidence Baseline

- Implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8` is the normal merge of completed T001 PR #449. It contains the reviewed production Fastfile repair and `scripts/tests/test_testflight_packaging.rb`; the separate planning branch retains the eight `specs/028-testflight-sigh-name/**` artifacts.
- `fastlane/Fastfile` at the implementation base already implements the required two-source neutralization, immediate per-call capture, target-specific guards, shell escaping, and archive/export reuse. It is a read-only compatibility surface for resumed work.
- The merged fixture already loads real Fastlane/Sigh and the repository Fastfile, invokes the real provisioning action with only `Sigh::Manager.start` and unrelated external boundaries replaced, and covers positive, stale missing-app/widget, fabricated-key, blank/equal, UUID, shell-safety, and export-reuse behavior.
- That fixture incorrectly activates and asserts exactly Fastlane 2.238.0 and treats independently PATH-selected `fastlane`, `gem`, and Ruby as one toolchain. On the observed local executor, unchanged `PATH` resolves a working Fastlane 2.241.0 wrapper whose own RubyGems context is not exposed by the independently selected system `ruby`/`gem`; the exact/independent-command premise therefore fails before behavioral tests despite Fastlane being installed.
- Historical failure run `38690610783` and VoxPocket PR #100 remain defect/provenance evidence; they do not override the current implementation base.
- Fastlane 2.241.0 source `get_provisioning_profile.rb` defines `SharedValues::SIGH_NAME`, copies `ENV["SIGH_NAME"]` into lane context, and returns the UUID.
- The same action contract is present on the required CI runner's Fastlane 2.238.0. The action assigns lane context only when `ENV["SIGH_NAME"]` is present; Sigh and the action do not clear a prior environment or lane-context name when a call publishes no name.
- Repository-wide inspection found exactly two fabricated production reads, both in `fastlane/Fastfile`; scripts contain no additional production read.
- App/widget custom specifier inputs and export reuse already exist and remain correct.
- `scripts/test-repoinfra.sh` is the existing PR-time RepoInfra entrypoint. At the implementation base it omits Ruby tests; MY-1820's preserved uncommitted candidate adds exactly one fixture invocation after Python discovery and before the Kimi contract test.
- Required CI runs `bash scripts/test-repoinfra.sh` on `macos-26` without installing Fastlane and exposes Fastlane 2.238.0. The new decision also requires a coherent newer installed Fastlane, such as observed 2.241.0, to work through its unchanged-PATH resolved toolchain. Version 2.238.0 is the minimum, not an exact pin.
- Decision `01a13f69-fbe2-76ad-aac4-8ff4d0b2c515`, accepted by Team Lead in `01a13f78-acd2-744f-bbc8-6ff51c847d3a`, supersedes only the prior exact-2.238.0 acceptance. It authorizes no installation, PATH workaround, formula/architecture assumption, alternate runtime, workflow edit, skip, or hook bypass.
- Planner-machine `bash scripts/test-repoinfra.sh` has unrelated Python 3.9 baseline failures (`X | None` import and unavailable `tomllib`); this does not weaken the required green implementation gate on the supported executor.

## Constitution Check

### Before design

- **Principles I–VII**: PASS. No health data, Swift, package, XcodeGen, AI, localization, or platform feature changes.
- **Quality Bar A**: PASS. The resumed dependency-free RepoInfra slice owns exactly two paths relative to the immutable implementation base; the merged Fastfile and all workflow/project/product surfaces are read-only.
- **Quality Bar D**: PASS. Existing release failure uses the established Fastlane error path; no new production force-cast/try/fatal behavior.
- **Quality Bar I**: PASS. The defect receives credential-free real-action coverage and no test is removed or weakened.
- **Quality Bar J**: PASS. AI Reviewer owns content review; PR Manager owns published CI/shipping state; Team Lead owns post-merge operational outcome.
- **Development Workflow / ADR-0021**: PASS. Planner publishes only Spec Kit artifacts from its separate workspace. The original Fullstack later resumes the preserved MY-1820 workspace, freezes the two-path local candidate for prepublication content review, and publishes only the permitted tree after PASS.

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
fastlane/Fastfile                          # merged T001 baseline; read-only
scripts/tests/test_testflight_packaging.rb # T002 resolver compatibility adaptation
scripts/test-repoinfra.sh                  # T002 mandatory invocation
```

**Structure Decision**: All affected paths belong to RepoInfra. The current candidate changes only the existing Ruby fixture and RepoInfra entrypoint. The merged Fastfile remains read-only, and the Ruby fixture stays separate from `test_testflight_freshness.py` so `027`'s classifier suite remains unchanged.

## Files in Scope

- `scripts/tests/test_testflight_packaging.rb` — resolve/use the actual unchanged-PATH Fastlane toolchain, enforce coherent version and minimum 2.238.0, preserve every substantive real-action assertion
- `scripts/test-repoinfra.sh` — minimal exactly-once invocation only; consume the fixture's canonical resolver rather than duplicate a divergent version policy

## Files NOT to Touch

- `fastlane/Fastfile`, now the merged T001 read-only production baseline
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

1. resolve `fastlane` from unchanged `PATH`, use the RubyGems toolchain actually selected/provided by that command, derive one actual version, require the CLI, corresponding gem, loaded library, and Fastlane/Sigh action sources to agree on that version, require it to be at least 2.238.0, and load real `fastlane`, `sigh`, and `sigh/manager` without a packaging-source, formula, or architecture-prefix assumption;
2. load the repository Fastfile rather than duplicating its profile logic;
3. snapshot and restore outer lane-context and Sigh environment state around each case, while preserving deliberate stale seeds inside each negative case until production performs its own pre-call neutralization;
4. replace only `Sigh::Manager.start` for profile/network installation and replace unrelated credential/build/upload external work;
5. invoke the real provisioning action twice with distinct target names and UUIDs and prove production neutralizes both stale name locations before each call;
6. separately pre-seed both locations for a missing app output and a missing widget output; require app-specific failure before widget/build work in the first case and widget-specific failure after preservation of the valid local app capture but before build work in the second;
7. prove scalar `SIGH_NAME` overwrite, immediate per-call capture, UUID non-use, blank/equal fail-closed behavior, shell-safe archive inputs, and matching export variables;
8. fail if production files use the fabricated target-derived environment-key convention, and retain every existing substantive case while removing only exact-version/independent-command assumptions;
9. make no network, credential, signing, upload, distribution, marker, or Developer Portal mutation.

`scripts/test-repoinfra.sh` must invoke the fixture exactly once through its canonical resolve-actual-fastlane contract rather than duplicate version-selection logic. Missing Fastlane, an unparseable or below-2.238.0 version, an absent corresponding gem/library, CLI/gem/loaded-library/source disagreement, or real-library load failure is a gate failure, not a skip, fallback, PATH rewrite, install request, or hook bypass. No `.github/**` edit is permitted.

## Dependency Strategy

```text
T001 merged RepoInfra per-call repair + broad real-action fixture baseline
  -> T002 actual-toolchain compatibility adaptation + mandatory RepoInfra gate wiring
       -> T003 freeze, verify, exact content review, unchanged publication, PR Manager handoff
            -> PR Manager merge with Owner gate
                 -> T004 Team Lead qualifying automatic TestFlight outcome proof on main
```

- T001 is satisfied by the merged base and owns no resumed edit. Its Fastfile behavior and broad fixture coverage are compatibility requirements.
- T002 records the necessary current-version adaptation within the same RepoInfra goal, approach, acceptance, and writer: it owns only the existing fixture's runtime-resolution repair and minimal mandatory test-entry wiring.
- T003 changes no source; findings return to T002 and any content change requires a new candidate review.
- T004 changes no repository file and belongs to Team Lead after merge. It observes the automatic `workflow_run` for successful CI on the exact merged head; it does not dispatch a release.

## Verification Strategy

Run from the repository root in the registered MY-1820 delivery checkout at implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8` plus the reviewed planning authority.

Keep executor `PATH` unchanged across discovery and verification. The fixture resolves `fastlane` from that PATH, enters only the actual toolchain selected/provided by that resolved command, and reports the resolved version, minimum comparison, and CLI/gem/loaded-library/source agreement before exercising the action. It may not choose an independently discovered alternative runtime.

1. Focused real-action regression: `ruby scripts/tests/test_testflight_packaging.rb`. The fixture must resolve the actual unchanged-PATH Fastlane toolchain, report one coherent version at or above 2.238.0, load the real Fastlane/Sigh/action sources from that version, and run all preserved cases.
2. Fastfile syntax: `ruby -c fastlane/Fastfile`.
3. Full RepoInfra gate:
   `bash scripts/test-repoinfra.sh`
4. Candidate hygiene:
   `git diff --check`
5. Scope proof relative to `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`: changed implementation paths are exactly the two Files in Scope; `fastlane/Fastfile` and every other Files NOT to Touch path have zero diff.

The resolver consumes the actual toolchain selected/provided by the unchanged-PATH Fastlane command; it neither assumes nor probes a formula layout and never mutates PATH. `scripts/test-repoinfra.sh` invokes that canonical contract exactly once, making the complete gate the fail-closed entrypoint. The real-action regression must remain mutation-sensitive to the fabricated/delayed reads and stale-state defects, and the full gate remains mandatory. Planner validation does not substitute for implementation evidence from both the observed newer local toolchain and required `macos-26` CI.

### Forbidden before reviewed merge

- `fastlane ios beta`
- Any dispatch of `.github/workflows/testflight.yml`
- Any App Store Connect upload, signing, profile generation outside the stubbed fixture, Developer Portal mutation, distribution, or release-marker mutation

### Post-merge operational evidence

After PR Manager reports merge, Team Lead observes the unchanged automatic TestFlight `workflow_run` produced by successful CI on the exact merged `main` SHA. Authoritative evidence is the Actions run URL, `automatic-ci` source, `workflow_run.head_sha`/gate candidate/run head matching the merged SHA, terminal conclusion, marker/result state, and uploaded build number. No release is dispatched for T004 and no secret or signing artifact is attached. A manual `force=false` run is supplemental only after the automatic run is terminal and its marker covers that exact SHA; `force=true` and any duplicate upload are forbidden, and manual evidence cannot replace a missing or failed automatic proof.

## Complexity Tracking

No constitutional exception, new layer, new package, new workflow, new release state, or ADR is required. The two-path T002 adaptation is the minimum correction authorized by the resolve-actual-fastlane decision; it adds no dependency and preserves merged production behavior.
