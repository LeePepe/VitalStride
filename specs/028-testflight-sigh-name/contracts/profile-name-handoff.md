# Contract: Per-call TestFlight profile-name handoff

## Base and precedence

- Implementation base: `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`.
- Planning lineage: this revision supersedes only the executor/task-boundary terms in reviewed planning revision `7c5fc64430c2b8dbf6c4216cf7e3203790c45821`; its per-call and post-merge decisions remain.
- This contract supersedes only the fabricated/delayed profile-name source statements in `specs/026-testflight-profile-reuse/**`.
- The target-specific project interface from `026` and all workflow/release policy accepted by `027` remain unchanged.

## Sequential fetch contract

1. Immediately before the app call, neutralize both `ENV["SIGH_NAME"]` and lane-context `SharedValues::SIGH_NAME`.
2. Fetch/install the app App Store profile with the existing API key, bundle ID, team, forced refresh, and installation behavior.
3. Before any widget fetch, immediately capture and validate the current real Fastlane lane-context profile name for the app.
4. Immediately before the widget call, independently neutralize both shared name locations again.
5. Fetch/install the widget App Store profile with its existing bundle ID and the same preserved options.
6. Immediately capture and validate the current real Fastlane lane-context profile name for the widget.
7. Validate target distinction before `build_app`.

## Source contract

- Supported name source: `lane_context[SharedValues::SIGH_NAME]` from the real provisioning action.
- Provenance mechanism: both the Sigh environment-backed name and the lane-context name are neutralized immediately before each real action; only the lane-context value captured immediately after that action is eligible.
- Action UUID return is not a name.
- Target-derived lowercase `sigh_*_profile-name` keys are forbidden production reads and forbidden diagnostic authority.
- Fixed display names, a second lookup, and cross-target fallback are forbidden.

## Validation contract

- Nil and whitespace-only values are invalid.
- Equal app/widget names are invalid.
- Missing app output raises an app-specific error before widget/build work. Missing widget output raises a widget-specific error after preserving the valid local app capture but before build work. All invalid state raises through the existing Fastlane user-facing error path before archive, upload, distribution, or release-marker mutation.
- Error text identifies the target and supported shared output without credentials, key material, certificates, keychain values, UUIDs, or profile contents.

## Consumer contract

| Target | Archive input | Export mapping |
|---|---|---|
| `VitalStride` | `VITALSTRIDE_APP_PROFILE_SPECIFIER` receives the shell-safe captured app name | `com.leepepe.vitalstride` receives the same app variable |
| `VitalStrideWidgets` | `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` receives the shell-safe captured widget name | `com.leepepe.vitalstride.widgets` receives the same widget variable |

No global profile override is added. `project.yml` remains unchanged.

## Real-action regression contract

The fixture:

- resolves `fastlane` from unchanged `PATH`, uses the RubyGems toolchain actually selected/provided by that resolved command, derives one Fastlane version, requires its CLI, corresponding gem, loaded library, and loaded Fastlane/Sigh action sources to agree on that version, requires the version to be at least 2.238.0, and loads the repository Fastfile without a packaging-source, formula, or architecture assumption;
- invokes the real provisioning-profile action;
- replaces `Sigh::Manager.start`, not the action;
- publishes distinct names and UUIDs for two sequential calls;
- proves the scalar shared name changes per call while the first target's captured value survives;
- proves production neutralizes both stale-capable name locations before each action;
- separately seeds stale values in both locations for missing app and missing widget output, then proves target-specific failure at the matching boundary without downstream build/upload work;
- proves missing, blank, and equal names stop before build/upload;
- proves shell-safe target mapping and exact-variable export reuse;
- prohibits fabricated convention reads in production `fastlane/**` and `scripts/**`;
- restores environment and lane context after each case;
- performs no network, signing, upload, distribution, workflow dispatch, marker mutation, or secret read.

The focused check and `scripts/test-repoinfra.sh` use the fixture's same canonical resolve-actual-fastlane contract. The gate runs the fixture exactly once and fails closed for missing Fastlane, an unparseable or below-minimum version, an absent corresponding gem/library, CLI/gem/loaded-library/source mismatch, or unavailable real library. It neither installs dependencies, mutates PATH, probes a packaging source, selects an alternate runtime/fallback, skips, bypasses hooks, nor requires a workflow edit. Fastlane 2.238.0 is the documented minimum; observed 2.241.0 is compatibility evidence, not a hard-coded target.

## Post-merge operational proof

- The authoritative T004 evidence is the qualifying automatic TestFlight `workflow_run` triggered by successful CI for the exact merged `main` SHA.
- Evidence binds the run URL, `automatic-ci` source, `workflow_run.head_sha`/gate candidate/run head to the merged SHA, terminal result, marker/result state, and uploaded build number.
- T004 dispatches no TestFlight run. `force=true` and duplicate upload are forbidden.
- A manual `force=false` run is supplemental only after the automatic run is terminal and its marker covers that exact SHA; it cannot satisfy T004 or replace missing/failed automatic proof.
- Authority: Owner-delegated decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9` (2026-10-15).

## Compatibility contract

- Preserve forced installed fetches, team/bundle identity, manual Release signing, Automatic base/Debug signing, build numbering, telemetry inputs, upload/distribution, classifier/orchestration, concurrency, and marker behavior.
- Preserve all existing tests and assertions.
- Relative to implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`, change only `scripts/tests/test_testflight_packaging.rb` and minimal mandatory wiring in `scripts/test-repoinfra.sh`; `fastlane/Fastfile` remains byte-for-byte unchanged.
