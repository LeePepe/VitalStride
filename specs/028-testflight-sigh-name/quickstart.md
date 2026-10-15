# Quickstart: Validate per-call TestFlight profile names

## Safety boundary

All implementation verification is credential-free. Do not run `fastlane ios beta`, dispatch `.github/workflows/testflight.yml`, sign/archive an app, contact App Store Connect, generate or install a real profile, upload/distribute a build, or move `testflight/last-released`.

## Prerequisites

- Work in MY-1815's registered delivery checkout at the exact reviewed planning revision.
- Use the repository's macOS/Homebrew Fastlane environment.
- Keep `.github/workflows/**`, `project.yml`, generated projects, product code, packages, and existing tests unchanged.

## 1. Baseline/red evidence

Before the production repair, add the real-action regression and run:

```sh
GEM_PATH="$(brew --prefix fastlane)/libexec" \
  "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb
```

Record failure against the current fabricated/delayed reads. Do not weaken the fixture to make the base pass.

## 2. Focused green checks

After the repair:

```sh
GEM_PATH="$(brew --prefix fastlane)/libexec" \
  "$(brew --prefix ruby)/bin/ruby" scripts/tests/test_testflight_packaging.rb

ruby -c fastlane/Fastfile
git diff --check
```

The Ruby output must show zero failures/errors and must come from the real Fastlane/Sigh action path.

## 3. Complete RepoInfra gate

```sh
bash scripts/test-repoinfra.sh
```

Read the full output. Require the Ruby regression to run and require zero failures/errors. A missing Fastlane/Sigh runtime is a gate failure, not a skip.

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

Fullstack follows the scoped VitalStride freeze/review/permission sequence, publishes the unchanged candidate, and proves local/remote/PR identity before PR Manager handoff. After merge, Team Lead runs the existing manual TestFlight workflow on `main` and records the run URL, terminal result, and uploaded build number on MY-1815.
