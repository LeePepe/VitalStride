# Quickstart: Validate per-call TestFlight profile names

## Safety boundary

All implementation verification is credential-free. Do not run `fastlane ios beta`, dispatch `.github/workflows/testflight.yml`, sign/archive an app, contact App Store Connect, generate or install a real profile, upload/distribute a build, or move `testflight/last-released`.

## Prerequisites

- Work in MY-1815's registered delivery checkout at the exact reviewed planning revision.
- Use a declared supported macOS/Homebrew executor: required CI currently provides Fastlane 2.238.0 and the release host provides 2.241.0. Resolve `brew --prefix fastlane` and `brew --prefix ruby` dynamically; never use ambient `/usr/bin/ruby` or a hard-coded ARM/Intel prefix.
- Keep `.github/workflows/**`, `project.yml`, generated projects, product code, packages, and existing tests unchanged.

## 1. Baseline/red evidence

Before the production repair, add the real-action regression and run:

```sh
GEM_PATH="$(brew --prefix fastlane)/libexec" \
  "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb
```

Record failure against the current fabricated/delayed reads. Also require two red-capable negatives: stale environment and lane context masking missing app output, and the same stale sources masking missing widget output after a valid app capture. Do not clear those deliberate seeds in fixture setup or weaken the fixture to make the base pass.

## 2. Focused green checks

After the repair:

```sh
GEM_PATH="$(brew --prefix fastlane)/libexec" \
  "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb

ruby -c fastlane/Fastfile
git diff --check
```

The Ruby output must show zero failures/errors, must come from the real Fastlane/Sigh action path, and must include the separate stale-seeded missing-app and missing-widget target-specific cases. Production, not fixture setup, neutralizes both shared name locations immediately before each real action.

## 3. Complete RepoInfra gate

```sh
bash scripts/test-repoinfra.sh
```

Read the full output. Require the Ruby regression to run exactly once through the same dynamically resolved formula-Ruby/Fastlane-`libexec` invocation as the focused command, and require zero failures/errors. A missing Homebrew, formula Ruby, Fastlane `libexec`, or real library is a gate failure, not a skip or install request.

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
