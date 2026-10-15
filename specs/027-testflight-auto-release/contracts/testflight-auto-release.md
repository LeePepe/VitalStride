# Contract: Minimal automatic TestFlight release

## Base and ownership

- Product base: `a6e31c6f44797fd95ebe50b96fe2310a3e52d789` on VitalStride `main`.
- Implementation base: the exact AI-Reviewer-passed v3 planning revision, or a Team-Lead-approved base containing byte-identical v3 artifacts.
- Owner layer: dependency-free `RepoInfra`.
- Implementation ceiling: `.github/workflows/testflight.yml`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`.
- Expected changed paths: workflow and classifier test; Fastfile remains unchanged.
- Explicit Owner approval is required for `.github/workflows/testflight.yml` before merge. AI review and CI cannot substitute.

## Event and candidate contract

Automatic input is a completed workflow named `CI`. Proceed only when conclusion is `success`, source event is `push`, and head branch is `main`.

Capture `workflow_run.head_sha` once. Checkout, range classification, lane context, and marker target use that exact candidate. Do not substitute a later `main` SHA.

The existing manual entry point is compatibility surface only. v3 defines no new manual-force policy or manual acceptance matrix.

## Marker and range contract

1. Fetch the history and tags required to resolve the candidate and remote `testflight/last-released`.
2. Require the marker to resolve to a commit that is an ancestor of the candidate. Missing, unreadable, non-commit, or non-ancestor state fails before release.
3. Parse NUL-safe change records for `testflight/last-released..candidate`.
4. Apply endpoint exclusions before positive matching. For rename/copy, either endpoint may qualify; relevant deletion qualifies; any relevant record makes a mixed range relevant.
5. An irrelevant range skips the existing lane and performs no marker mutation.
6. A relevant range invokes the existing `fastlane ios beta` lane once.
7. Only after that lane reports successful upload may the workflow move `testflight/last-released` to the exact candidate.
8. A failure before the marker step leaves the marker unchanged. Configure no automatic retry or rollback.

The marker is the sole durable release state. Do not create/read per-SHA records, a second marker, queue/cursor, CAS/lease, transaction journal, pending/resolved state, or recovery ref.

## App relevance contract

Positive shipped paths are:

- `Packages/*/Package.swift`, `Packages/*/Sources/**`, `Packages/*/Plugins/**`
- `VitalStride/Sources/**`, `VitalStride/Resources/**`, `VitalStride/Assets.xcassets/**`, `VitalStride/*.entitlements`
- `VitalStrideMac/Sources/**`, `VitalStrideMac/Resources/**`, `VitalStrideMac/Assets.xcassets/**`, `VitalStrideMac/*.entitlements`
- `VitalStrideWatch Watch App/Sources/**`, `VitalStrideWatch Watch App/Resources/**`, `VitalStrideWatch Watch App/Assets.xcassets/**`, `VitalStrideWatch Watch App/*.entitlements`
- `VitalStrideWidgets/**/*.swift`, `VitalStrideWidgets/**/*.plist`, `VitalStrideWidgets/**/*.entitlements`, `VitalStrideWidgets/**/*.xcassets/**`
- exact `project.yml`, `fastlane/Fastfile`, and `fastlane/Appfile`

Documentation/context, specs, package/app tests, `Prototype/**`, generated project output, `.github/**`, CI-only scripts, and every unlisted path do not independently qualify.

## Existing lane compatibility contract

- Reuse the existing `fastlane ios beta` build/upload lane unchanged.
- Preserve existing runner labels `self-hosted` and `vitalstride-mac`.
- Preserve signing, profiles, keychain, App Store Connect secrets, version/build handling, telemetry inputs, and safe-log behavior.
- Add no secret, release service, workflow, runner, or schedule.
- v3 adds no shadow-policy tests for these preserved internals.

## Concurrency and permission contract

- One stable app-scoped TestFlight concurrency group.
- `cancel-in-progress: false`.
- Job-level `contents: write`; no broader GitHub permission.
- No custom durable queue or FIFO guarantee.

## Regression contract

The classifier unit test proves only the v3 behavior:

1. exact automatic workflow/conclusion/event/branch guards and one captured candidate;
2. marker resolution and literal `marker..candidate` range;
3. accepted path positives and exclusion precedence, including NUL-safe mixed, deletion, rename, and copy records;
4. root-only entitlement positives for `VitalStride/*.entitlements`, `VitalStrideMac/*.entitlements`, and `VitalStrideWatch Watch App/*.entitlements`, plus one nested-entitlement negative case under each root;
5. all four fully prefixed `VitalStrideWidgets/**` families and outside-root negative suffix cases;
6. irrelevant skip, relevant lane decision, and invalid-marker failure;
7. existing-lane call followed by candidate marker update only on lane success;
8. one non-cancelling group, job-level `contents: write`, and absence of auxiliary state/retry/rollback.

Workflow lint is:

```bash
actionlint .github/workflows/testflight.yml
```

The repository does not provision `actionlint`; the executor must provide it. Tests and lint perform no GitHub write, signing, upload, App Store Connect request, or tag mutation.

The mandatory repository-level gate also runs from the repository root:

```bash
bash scripts/test-repoinfra.sh
```

Its full output must report zero failures/errors. It supplements the two feature-specific checks and is not waived or reclassified as a shadow-policy suite. No standalone Ruby syntax, XcodeGen/xcodebuild/SwiftPM, Fastlane execution, production workflow, or feature-specific shadow-policy suite is part of v3 acceptance.

## Delivery contract

- T001 implements the two-path candidate.
- T002 freezes it, runs the two feature-specific checks and mandatory RepoInfra gate, then commits, pushes, and creates or updates the single non-Draft candidate PR.
- Before exact-candidate review, T002 proves local `HEAD`, remote branch OID, and PR `headRefOid` are the same published SHA; review binds to that SHA.
- A finding returns to T001; T002 does not repair source. Any content change requires a fresh published SHA, three-way identity proof, and review.
- After PASS, T002 re-proves the same three-way identity and hands the reviewed SHA to PR Manager.
- PR Manager owns required checks and merge.
- Explicit Owner approval for the workflow remains mandatory before merge.
