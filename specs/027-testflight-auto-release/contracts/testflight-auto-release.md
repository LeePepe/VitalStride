# Contract: TestFlight auto-release

## Exact Base and Ownership

- Planning product base: `a6e31c6f44797fd95ebe50b96fe2310a3e52d789` on VitalStride `main`.
- Implementation base: the exact AI-Reviewer-passed planning revision, or a Team-Lead-approved base containing byte-identical reviewed artifacts.
- Implementation owner layer: dependency-free `RepoInfra`.
- Exact implementation allowlist: `.github/workflows/testflight.yml`, `fastlane/Fastfile`, `scripts/tests/test_testflight_freshness.py`.
- `.github/workflows/testflight.yml` requires explicit Owner approval before merge; AI PASS, CI, or absent CODEOWNERS enforcement cannot substitute.

## Event Contract

Automatic input is a completed workflow named `CI`; proceed only for a successful `push` on `main`. Candidate is exact source `head_sha`.

Manual input is `workflow_dispatch` with boolean `force`, default `false`. Candidate is exact current remote `main` captured once.

Both paths converge before marker relation, relevance, candidate-PR/version, and release evaluation. No later moving branch SHA is substituted.

## Marker Contract

1. Fetch full history and the remote `testflight/last-released` tag.
2. Use only that tag as durable release state. Do not create/read per-SHA attempt/skip records, custom queue/cursor refs, CAS/lease state, transaction journals, or auxiliary recovery refs.
3. If absent, select the Git empty tree as ephemeral baseline. If marker is an ancestor of candidate, select `marker..candidate`. If candidate equals or is an ancestor of marker, skip as already covered. Unreadable/non-commit/divergent state fails closed.
4. Classify the selected range. Automatic and manual `force=false` skip an ineligible range without writing state. Manual `force=true` may bypass only this relevance result for exact current `main`.
5. Run candidate-PR/version validation and the critical release lane.
6. Only after every earlier critical phase succeeds, move the sole remote marker to candidate and freshly read it back. Exact candidate readback is required for success.
7. Any earlier failure invokes no marker command. Marker update/readback failure is terminal, records safe evidence, creates no compensating state, and performs no retry/rollback. The next run freshly reads the remote marker and applies this contract; no assertion is made about an unobservable remote acknowledgement.

## App-Relevance Contract

Baseline-to-candidate change records are NUL-safe. Exclusions apply per endpoint before positive matching. A relevant deletion qualifies; either relevant rename/copy endpoint qualifies; excluded-to-excluded does not; a mixed diff qualifies when any record is relevant.

Positive shipped paths are:

- `Packages/*/Package.swift`, `Packages/*/Sources/**`, `Packages/*/Plugins/**`
- shipped `Sources/**`, `Resources/**`, `Assets.xcassets/**`, and `*.entitlements` families under `VitalStride`, `VitalStrideMac`, and `VitalStrideWatch Watch App`
- `VitalStrideWidgets/**/*.swift`, `**/*.plist`, `**/*.entitlements`, `**/*.xcassets/**`
- exact `project.yml`, `fastlane/Fastfile`, `fastlane/Appfile`

Documentation/context, specs, package/app tests, `Prototype/**`, generated project output, `.github/**`, CI-only scripts, and every unlisted path do not independently qualify.

## Merged-PR and Version Contract

- Each automatic/manual candidate resolves exactly one merged PR for that exact SHA and based on `main`; zero/multiple matches fail before archive. Force does not bypass this.
- Only the exact candidate PR's case-sensitive `release:minor` label is considered; labels on earlier PRs inside the accumulated range do not apply.
- Shipping target versions in `project.yml` must agree and be numeric major/minor or major/minor/patch.
- No label: use project value. Label: increment minor and reset an existing patch to zero.
- The runtime value is not written to tracked files and is reused by archive, lookup, distribution, summary, and issue evidence.
- Build number remains maximum across all TestFlight marketing versions plus one and is exposed safely.

## Release-Critical Contract

Critical failures stop the run: candidate/source/marker validation, candidate-PR/label lookup, project-version validation, secret/keychain/profile checks, archive, binary upload, Apple processing, internal-group distribution, dSYM publication, and final marker update/readback.

No automatic retry, rescue-and-continue, `continue-on-error`, or rollback is permitted for those phases. TEMP-PRELAUNCH remains warning-only under its existing accepted internal-TestFlight policy. Optional Aptabase inputs preserve their current safe-empty behavior.

## Concurrency and Runner Contract

- One app-scoped TestFlight concurrency group; `cancel-in-progress: false`.
- Runner labels include exactly `self-hosted` and `vitalstride-mac`.
- No custom durable queue, queue ref, cursor, FIFO promise, second runner, schedule, or release workflow.
- The accumulated marker range makes superseded/omitted pending platform events safe: a later executed candidate includes all changes since the last success.

## Secret and Permission Contract

- Reuse existing ASC, keychain, GlitchTip, Aptabase, signing-profile, and GitHub token inputs; add no secret and print no value.
- GitHub permissions are limited to exact candidate-PR/label reads plus the sole marker write/read.
- Evidence excludes profile/certificate/keychain contents and names.

## Evidence Contract

Every skip/failure writes exact candidate SHA, source, marker relation/baseline, decision or phase, stable reason code, and safe next action. Marker update failure records only the push result and last safely observed marker; it creates no recovery state and makes no unobservable-state assertion.

Success additionally writes run URL, marketing version, build number, and confirmed marker SHA equal to candidate.

After merge, MY-1766 receives the first eligible successful run's exact SHA, URL, terminal conclusion, marketing version, build number, and confirmed marker. A failed run is incident-only. The forward path is a later eligible merge or manual current-main run; neither is configured as an automatic retry.

## Regression Contract

Credential-free tests must prove:

1. automatic event name/event/branch/conclusion guards and exact-SHA reuse;
2. empty-tree bootstrap plus ancestor/equal/stale/divergent marker relations;
3. narrow accumulated path positives and endpoint exclusions across docs, package tests/contexts, mixed, deletion, rename/copy, and several irrelevant merges followed by a relevant merge;
4. relevant release failure leaves the baseline unchanged and a later candidate range picks it up;
5. manual force default, relevance-only bypass, same-released protection, and failed-current-main pickup;
6. one concurrency group, non-cancellation, and absence of custom durable queue/cursor/attempt state;
7. automatic/manual exact candidate-PR label and marketing-version handoff;
8. app-wide build query and safe output;
9. critical failure ordering, marker-after-success/readback, no auxiliary state, no automatic retry/rollback, and summary fields;
10. all pre-existing profile/signing/shell-safety assertions remain effective.

Tests perform no GitHub write, ASC request, profile installation, signing action, dispatch, or upload.
