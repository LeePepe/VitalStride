# Quickstart: Validate per-call TestFlight profile names

## Safety boundary

All implementation verification is credential-free. Do not run `fastlane ios beta`, dispatch `.github/workflows/testflight.yml`, sign/archive an app, contact App Store Connect, generate or install a real profile, upload/distribute a build, or move `testflight/last-released`.

## Prerequisites

- Work in MY-1820's preserved delivery checkout at implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`, with the exact revised planning authority supplied by Team Lead.
- Keep executor `PATH` unchanged. Resolve `fastlane` from it and use only the actual RubyGems toolchain selected/provided by that command. Do not install a dependency, mutate PATH, probe a formula/architecture layout, choose an alternate runtime/fallback, skip, or bypass hooks.
- Require one resolved Fastlane version across CLI, corresponding gem, loaded library, and loaded action/Sigh sources. The version must be at least 2.238.0. The fixture's bootstrap may enter only the resolved Fastlane command's own toolchain; independently discovering a different Ruby/gem runtime is forbidden.
- Keep `.github/workflows/**`, `project.yml`, generated projects, product code, packages, and every test other than the authorized fixture bootstrap unchanged; preserve every substantive fixture assertion.

## 1. Baseline/red evidence

Historical red evidence and the merged T001 implementation are already recorded at base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`. Do not reopen production. Before changing the resolver, confirm the old fixture rejects a supported newer actual Fastlane solely because it pins 2.238.0; then preserve that output as the resolver red case.

Use the canonical focused entrypoint:

```sh
command -v fastlane
fastlane --version
ruby scripts/tests/test_testflight_packaging.rb
```

Record that the failure is the superseded exact-version/independent-command premise, not a behavioral test. Do not edit `fastlane/Fastfile`, clear deliberate stale seeds in fixture setup, or weaken any existing case to make the base pass.

## 2. Focused green checks

After the repair:

```sh
command -v fastlane
fastlane --version
ruby scripts/tests/test_testflight_packaging.rb

ruby -c fastlane/Fastfile
git diff --check
```

The presence and version checks are assertions, not diagnostics: the fixture must report the unchanged-PATH Fastlane command, one resolved version at or above 2.238.0, and exact CLI/gem/loaded-library/action-source agreement before behavioral cases are accepted. The Ruby output must show zero failures/errors, must come from the real Fastlane/Sigh action path, and must include every pre-existing positive, stale-seeded missing-app/widget, fabricated-key, blank/equal, UUID, shell-safety, and export-reuse case. Production, not fixture setup, neutralizes both shared name locations immediately before each real action.

## 3. Complete RepoInfra gate

```sh
bash scripts/test-repoinfra.sh
```

Read the full output. Require the Ruby regression to run exactly once through the same canonical resolve-actual-fastlane contract as the focused command, and require zero failures/errors. Missing Fastlane, an unparseable or below-2.238.0 version, an absent corresponding gem/library, any CLI/gem/loaded-library/source mismatch, or real-library load failure is a gate failure, not a skip, fallback, PATH workaround, install request, or hook bypass.

## 4. Scope and compatibility proof

```sh
git diff --name-only 49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8...HEAD
git diff --exit-code 49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8...HEAD -- \
  fastlane/Fastfile .github project.yml VitalStride.xcodeproj \
  scripts/tests/test_testflight_freshness.py \
  VitalStride VitalStrideMac 'VitalStrideWatch Watch App' VitalStrideWidgets Packages Prototype
```

The implementation manifest contains only:

- `scripts/tests/test_testflight_packaging.rb`
- `scripts/test-repoinfra.sh`

## 5. Delivery and production evidence

Fullstack follows the scoped VitalStride freeze/review/permission sequence, publishes the unchanged candidate, and proves local/remote/PR identity before PR Manager handoff. After merge, Team Lead observes the qualifying automatic TestFlight `workflow_run` triggered by successful CI for the exact merged `main` SHA and records the run URL, `automatic-ci` source, matching workflow/gate/run head identity, terminal result, marker/result state, and uploaded build number on MY-1815. T004 dispatches no release; `force=true` is forbidden, and any later manual `force=false` run is supplemental only after the automatic run is terminal and marker-covers that SHA.
