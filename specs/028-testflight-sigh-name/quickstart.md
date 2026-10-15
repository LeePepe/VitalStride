# Quickstart: Validate per-call TestFlight profile names

## Safety boundary

All implementation verification is credential-free. Do not run `fastlane ios beta`, dispatch `.github/workflows/testflight.yml`, sign/archive an app, contact App Store Connect, generate or install a real profile, upload/distribute a build, or move `testflight/last-released`.

## Prerequisites

- Work in MY-1815's registered delivery checkout at the exact reviewed planning revision.
- Use the required `macos-26` CI executor. Its runner image exposes RubyGems Fastlane 2.238.0 through its own `fastlane`, `gem`, and Ruby commands on `PATH`. Do not require or probe a Homebrew formula, install a dependency, or choose a fallback runtime.
- Keep that executor-provided `PATH` unchanged across all commands below. Every `ruby` invocation, including `ruby -c`, must be the executable reported by `command -v ruby`; the fixture asserts the loaded Fastlane library version before exercising the action.
- Keep `.github/workflows/**`, `project.yml`, generated projects, product code, packages, and existing tests unchanged.

## 1. Baseline/red evidence

Before the production repair, add the real-action regression and run:

```sh
command -v fastlane
command -v gem
command -v ruby
fastlane --version
gem list --local --exact fastlane
ruby scripts/tests/test_testflight_packaging.rb
```

Record failure against the current fabricated/delayed reads. Also require two red-capable negatives: stale environment and lane context masking missing app output, and the same stale sources masking missing widget output after a valid app capture. Do not clear those deliberate seeds in fixture setup or weaken the fixture to make the base pass.

## 2. Focused green checks

After the repair:

```sh
command -v fastlane
command -v gem
command -v ruby
fastlane --version
gem list --local --exact fastlane
ruby scripts/tests/test_testflight_packaging.rb

ruby -c fastlane/Fastfile
git diff --check
```

The presence and version checks are assertions, not diagnostics: the selected CLI, local RubyGems inventory, and Fastlane library loaded by the selected Ruby must all report exactly 2.238.0 before the test is accepted. The Ruby output must show zero failures/errors, must come from the real Fastlane/Sigh action path, and must include the separate stale-seeded missing-app and missing-widget target-specific cases. Production, not fixture setup, neutralizes both shared name locations immediately before each real action.

## 3. Complete RepoInfra gate

```sh
bash scripts/test-repoinfra.sh
```

Read the full output. Require the Ruby regression to run exactly once through the same PATH/RubyGems resolver and 2.238.0 CLI/gem/library agreement check as the focused command, and require zero failures/errors. A missing command, absent gem, mismatch, or real-library load failure is a gate failure, not a skip, fallback, or install request.

## 4. Scope and compatibility proof

```sh
git diff --name-only <reviewed-planning-sha>...HEAD
git diff --exit-code <reviewed-planning-sha>...HEAD -- \
  .github project.yml VitalStride.xcodeproj \
  scripts/tests/test_testflight_freshness.py \
  VitalStride VitalStrideMac 'VitalStrideWatch Watch App' VitalStrideWidgets Packages Prototype
```

The implementation manifest contains only:

- `fastlane/Fastfile`
- `scripts/tests/test_testflight_packaging.rb`
- `scripts/test-repoinfra.sh`

## 5. Delivery and production evidence

Fullstack follows the scoped VitalStride freeze/review/permission sequence, publishes the unchanged candidate, and proves local/remote/PR identity before PR Manager handoff. After merge, Team Lead observes the qualifying automatic TestFlight `workflow_run` triggered by successful CI for the exact merged `main` SHA and records the run URL, `automatic-ci` source, matching workflow/gate/run head identity, terminal result, marker/result state, and uploaded build number on MY-1815. T004 dispatches no release; `force=true` is forbidden, and any later manual `force=false` run is supplemental only after the automatic run is terminal and marker-covers that SHA.
