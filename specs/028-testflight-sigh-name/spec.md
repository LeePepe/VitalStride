# Feature Specification: TestFlight per-call SIGH_NAME capture

**Planning version**: MY-1815/v1
**Feature Branch**: `028-testflight-sigh-name`
**Created**: 2026-10-15
**Status**: Ready for final targeted independent planning review
**Target**: `LeePepe/VitalStride@main`
**Product base**: `663054cb4e7f58459fd0caf6a0710f6e74f18bd0`
**Authority**: MY-1815 revision 3; Team Lead handoff `01a13e2f-04fa-7e65-b7cd-020c292d187a`; Owner-delegated T004 decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9`; Owner-delegated targeted resolver decision `01a13e62-b073-7793-be99-b003a939de0f` (2026-10-15)

## Intent

Repair the TestFlight lane so each target neutralizes both stale Sigh environment state and stale lane-context name state before its real `get_provisioning_profile` call, then captures the profile display name that call publishes through `lane_context[SharedValues::SIGH_NAME]` immediately afterward. Preserve the existing fail-closed checks and app/widget archive-export mapping. Add a credential-free regression that loads the real Fastlane/Sigh action, proves stale values cannot satisfy a missing current-call output, and rejects the fabricated target-derived environment-key convention.

This revision narrowly supersedes the incorrect profile-name source statements in `specs/026-testflight-profile-reuse/**`. It preserves that feature's valid target-specific signing interface and all behavior accepted by `specs/027-testflight-auto-release/**`.

## Decision Register

- **DEC-028-001 — Supported source**: Fastlane 2.238.0 and 2.241.0 conditionally publish the fetched profile display name as `SharedValues::SIGH_NAME` in lane context when `ENV["SIGH_NAME"]` is present. The action return is the profile UUID, not the name.
- **DEC-028-002 — Fresh per-call provenance**: `ENV["SIGH_NAME"]` and lane-context `SharedValues::SIGH_NAME` are independently stale-capable scalar state because Fastlane publishes a name only when the current call supplies one. Immediately before every real provisioning call, production must neutralize both locations; it must then capture the lane-context name immediately after that call and before any later call.
- **DEC-028-003 — Fail closed**: Missing or blank current-call output, or equal captured target values, terminates with target-specific evidence before `build_app`, upload, distribution, or release-marker mutation. No stale value, return-value, fixed-name, target-copy, or fabricated-env fallback is allowed.
- **DEC-028-004 — Real-action regression**: The regression loads real `fastlane`, `sigh`, and `sigh/manager`, invokes the real provisioning-profile action, and replaces only the external `Sigh::Manager.start` boundary. It may not stub the action or manufacture its return as a display name. Separate missing-app and missing-widget cases deliberately seed stale environment and lane-context values and prove production neutralization defeats both.
- **DEC-028-005 — Narrow compatibility**: The repair changes no workflow, XcodeGen/project setting, signing identity, bundle identifier, build-number, upload/distribution, telemetry, relevance, concurrency, or marker behavior.
- **DEC-028-006 — Delivery and production proof**: Fullstack owns the reviewed RepoInfra candidate and PR. After merge, the qualifying automatic TestFlight `workflow_run` triggered by successful CI on the exact merged `main` head is the authoritative T004 proof. Team Lead records its run/head identity, terminal result, and uploaded build number on MY-1815. No duplicate upload is authorized; a later manual `force=false` run is supplemental only and `force=true` is forbidden for T004.
- **DEC-028-007 — Supported executor contract**: The focused regression and mandatory RepoInfra gate resolve the required CI executor's own `fastlane`, `gem`, and Ruby commands from `PATH`. They require the selected Fastlane CLI, RubyGems inventory, and loaded Fastlane library to agree on the runner image's Fastlane 2.238.0. A missing command, absent gem, version mismatch, or load failure stops the gate; no Homebrew-formula requirement, dependency installation, workflow edit, or fallback is allowed. The release host's formula-packaged 2.241.0 remains production action-compatibility evidence, not test-runtime authority.

## User Scenarios & Testing

### User Story 1 - Archive with each profile fetched in this run (Priority: P1)

As the release operator, I need the app and widget to use the display names returned by their own current-run profile fetches so the archive can proceed without relying on a nonexistent environment-key convention.

**Independent Test**: A credential-free fixture drives the real Fastlane provisioning action twice with distinct names and UUIDs, then proves the actual lane neutralizes stale state at each call boundary, captures the first name before the second call overwrites shared state, and maps both names to the correct archive and export targets. Separate stale-seeded cases prove a missing current app or widget name cannot reuse prior state.

**Acceptance Scenarios**:

1. **US1/AC1** — Given the app fetch publishes `APP_PROFILE_A`, when the widget fetch begins, then the lane has already captured `APP_PROFILE_A` for the app.
2. **US1/AC2** — Given the widget fetch publishes `WIDGET_PROFILE_B`, when the lane assembles archive and export configuration, then the widget uses `WIDGET_PROFILE_B` and the app still uses `APP_PROFILE_A`.
3. **US1/AC3** — Given either call publishes no current name or a blank current name, when the lane validates the handoff, then it terminates before archive, upload, distribution, or marker mutation and identifies the affected target without exposing credentials or profile contents.
4. **US1/AC4** — Given both calls publish the same display name, when the lane validates target distinction, then it terminates before archive instead of mapping one profile to both bundle identifiers.
5. **US1/AC5** — Given a profile name contains spaces or shell-significant characters, when the lane passes archive inputs, then the complete value remains opaque, shell-safe, and target-correct, and export reuses the same captured variable.
6. **US1/AC6** — Given both supported name locations contain stale values before the app call and that call publishes no current name, when the lane executes the app boundary, then it identifies the app failure and stops before the widget call or build work.
7. **US1/AC7** — Given the app was captured successfully, both supported name locations are stale-seeded before the widget call, and that call publishes no current name, when the lane executes the widget boundary, then it identifies the widget failure, preserves the local app capture, and stops before build work.

### User Story 2 - Reject profile-output drift before release (Priority: P1)

As the delivery owner, I need the repository gate to exercise Fastlane's real output contract without Apple access so a fabricated key, action stub, UUID fallback, or delayed capture cannot reach the release runner.

**Independent Test**: The Ruby regression loads the repository Fastfile and the installed Fastlane/Sigh libraries through required CI's PATH-selected RubyGems runtime, stubs only network/profile-install work at `Sigh::Manager.start`, invokes the real action for app then widget, and observes fresh-call provenance, fail-closed lane behavior, and target-correct build inputs.

**Acceptance Scenarios**:

1. **US2/AC1** — Given two real action invocations publish distinct `SIGH_NAME` and `SIGH_UUID` values, when they complete sequentially, then production clears both stale name locations before each call, lane context exposes each current call's name at that boundary, the second call overwrites shared `SIGH_NAME`, and neither UUID is used as a display name.
2. **US2/AC2** — Given the historical `sigh_<bundle-id>_appstore_profile-name` convention appears as a production read anywhere in `fastlane/**` or `scripts/**`, when the regression runs, then it fails.
3. **US2/AC3** — Given the focused Ruby regression is added, when `bash scripts/test-repoinfra.sh` runs, then that regression is executed through the existing RepoInfra gate with real Fastlane/Sigh loading and no Apple credentials or network call.
4. **US2/AC4** — Given the current automatic-release classifier tests and workflow, when this repair is delivered, then their files and behavior remain unchanged.
5. **US2/AC5** — Given the required `macos-26` CI executor provides RubyGems Fastlane 2.238.0 through its own `fastlane`, `gem`, and Ruby commands on `PATH`, when the focused test and RepoInfra gate run, then they require all three version surfaces to agree on 2.238.0 before loading the real libraries; a missing command, absent gem, mismatch, or load failure fails the gate instead of skipping or falling back.

### User Story 3 - Confirm the repaired path in TestFlight (Priority: P1)

As the delivery lead, I need the qualifying automatic post-merge run from `main` to confirm the repaired signing handoff uploads a build successfully without creating a duplicate release.

**Independent Test**: After the reviewed PR merges, Team Lead observes the automatic TestFlight `workflow_run` created by successful CI for the exact merged head and records its Actions run URL, source/head identity, terminal result, and uploaded build number on MY-1815.

**Acceptance Scenarios**:

1. **US3/AC1** — Given the reviewed repair is merged to `main` and CI succeeds for that exact merged head, when the existing automatic TestFlight workflow runs, then its `workflow_run` head/gate candidate equals the merged SHA and it uses the unchanged release policy and repaired per-call names.
2. **US3/AC2** — Given the run succeeds, when evidence is recorded, then MY-1815 contains the run URL and uploaded build number without credential, certificate, keychain, or profile contents.
3. **US3/AC3** — Given the run fails, when evidence is recorded, then the issue remains open with the exact failing step and no false completion claim.
4. **US3/AC4** — Given the automatic run is authoritative, when operational evidence is collected, then no forced duplicate is dispatched; any later manual `force=false` run occurs only after the automatic run is terminal and the exact SHA is marker-covered, remains supplemental, and cannot replace missing or failed automatic proof.

### Edge Cases

- The app call succeeds but publishes no usable name: fail before the widget value can mask the app failure.
- The widget call overwrites shared context: preserve the already captured app name.
- The action returns a UUID while publishing a different display name: use only the display name.
- A prior lane run or prior target left either supported `SIGH_NAME` location populated and the current call publishes no name: production clears both locations before the call, and stale-seeded real-action cases prove target-specific failure.
- A contributor retains the fabricated convention only in an error message: replace it with supported-output wording so repository-wide regression checks do not normalize the invalid contract.
- Fastlane/Sigh is unavailable or does not match the required CI image's asserted 2.238.0 runtime: fail the test gate rather than silently skip, install, or choose another runtime.

## Requirements

### Functional Requirements

- **FR-001**: The lane MUST retain separate forced, installed App Store profile fetches for `com.leepepe.vitalstride` and `com.leepepe.vitalstride.widgets`.
- **FR-002**: Immediately before the app fetch, the lane MUST neutralize both `ENV["SIGH_NAME"]` and `lane_context[SharedValues::SIGH_NAME]`; immediately after the fetch and before the widget fetch, it MUST capture the current lane-context value as the app profile name.
- **FR-003**: Immediately before the widget fetch, the lane MUST neutralize both `ENV["SIGH_NAME"]` and `lane_context[SharedValues::SIGH_NAME]`; immediately after the fetch, it MUST capture the current lane-context value as the widget profile name.
- **FR-004**: The lane MUST reject a missing or blank current-call name, or non-distinct captured names, with target-specific evidence before `build_app`.
- **FR-005**: The app and widget captured variables MUST remain the sole sources for their matching archive specifier and export bundle mapping.
- **FR-006**: The action return UUID, fixed display names, target-derived `sigh_*_profile-name` keys, and copying one target's name to the other MUST NOT be fallback sources.
- **FR-007**: Profile display names MUST remain shell-safe opaque values and MUST NOT expose credentials, profile contents, certificates, or keychain state.
- **FR-008**: A Ruby regression MUST resolve `fastlane`, `gem`, and Ruby from the required executor's `PATH`, assert that the selected CLI, RubyGems inventory, and loaded library agree on Fastlane 2.238.0, require the real `fastlane`, `sigh`, and `sigh/manager` libraries, and invoke the real `GetProvisioningProfileAction` path without a Homebrew-formula or architecture-prefix assumption.
- **FR-009**: The regression MAY replace only external build/upload/credential work and `Sigh::Manager.start`; it MUST NOT stub `get_provisioning_profile`, `GetProvisioningProfileAction`, lane context publication, or action return semantics.
- **FR-010**: The regression MUST prove two sequential calls publish distinct names, shared `SIGH_NAME` is per-call/overwritten, UUIDs stay distinct from names, the actual Fastfile lane neutralizes both stale sources before every call, and capture occurs immediately after the matching call.
- **FR-011**: The regression MUST fail for any production read of the fabricated `sigh_<bundle-id>_appstore_profile-name` convention in `fastlane/**` or `scripts/**`.
- **FR-012**: The existing RepoInfra gate MUST execute the Ruby regression exactly once through the same PATH/RubyGems resolver and version assertion as the focused check, and MUST fail closed for a missing command, absent or non-2.238.0 Fastlane gem, CLI/gem/library version mismatch, or real-library load failure.
- **FR-013**: No existing TestFlight classifier assertion or RepoInfra assertion may be deleted or weakened.
- **FR-014**: `.github/workflows/testflight.yml`, `project.yml`, generated projects, application/package code, and signing/upload/release-state behavior MUST remain unchanged.
- **FR-015**: After merge, Team Lead MUST treat the qualifying automatic TestFlight `workflow_run` for successful CI on the exact merged `main` head as authoritative and record its run URL, source/head identity, terminal result, and uploaded build number on MY-1815.
- **FR-016**: The regression MUST separately pre-seed stale environment and lane-context names for a missing app output and for a missing widget output, and MUST prove target-specific failure at the matching boundary before disallowed downstream work.
- **FR-017**: T004 MUST NOT dispatch `force=true` or any duplicate upload. A manual `force=false` run is supplemental only after the automatic run is terminal and marker-covers the exact merged SHA; it cannot satisfy T004 or substitute for missing/failed automatic proof.

## Existing Behaviour

- `fastlane/Fastfile` performs two separate `get_provisioning_profile` calls with `force: true` and `skip_install: false`, first for the app and then for the widget.
- After both calls, the lane reads two target-derived lowercase environment keys that Fastlane's Sigh action never publishes. Both values are therefore nil and the current guard aborts before archive.
- Fastlane 2.238.0/2.241.0's real action reads `ENV["SIGH_NAME"]` from Sigh, writes it to `Actions.lane_context[SharedValues::SIGH_NAME]` only when a name exists, and returns `SIGH_UUID`. Neither Sigh nor the action clears an older environment or lane-context name when the current call supplies none, so both locations can remain stale.
- The lane already rejects missing/blank names and equal names before `build_app`, shell-escapes each archive value, and reuses the same variables for export.
- `project.yml` already maps `VITALSTRIDE_APP_PROFILE_SPECIFIER` and `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` to the correct Release targets. No project change is needed.
- `scripts/tests/test_testflight_freshness.py` covers the automatic-release workflow/classifier but does not exercise Fastlane profile output.
- `scripts/test-repoinfra.sh` runs shell/Python checks and the existing RepoInfra tests but does not yet run a real-action Fastlane Ruby regression.

## Compatibility

- Preserve both bundle identifiers, team ID, forced refresh, installation, Manual Release signing, Apple Distribution identity, base/Debug Automatic signing, and the existing target-specific project keys.
- Preserve missing/blank/equal fail-closed guards, shell escaping, archive/export variable reuse, and failure before upload or marker movement.
- Preserve XcodeGen, build-number calculation, telemetry inputs, App Store Connect API-key handling, upload, internal-group distribution, TestFlight relevance, concurrency, manual compatibility, and marker semantics.
- Preserve every assertion in `scripts/tests/test_testflight_freshness.py` and all unrelated RepoInfra tests.
- Preserve the path ceiling as one RepoInfra goal and one implementation PR.
- Preserve the automatic post-merge release trigger; do not authorize a duplicate upload or treat a racing/default manual run as authoritative evidence.

## Removed Behaviour

- **RB-001**: Remove all production reads and diagnostic claims for `sigh_<bundle-id>_appstore_profile-name`. **Authority**: DEC-028-001 and MY-1815 diagnosis.
- **RB-002**: Remove delayed app-name resolution after the widget call. Each scalar output is captured at its own call boundary. **Authority**: DEC-028-002.
- **RB-003**: Remove no fail-closed guard and weaken no existing test. **Authority**: DEC-028-003 and DEC-028-005.
- **RB-004**: Remove no workflow, signing, upload, distribution, build-number, telemetry, or release-state behavior. **Authority**: DEC-028-005.
- **RB-005**: Remove the default manual run as unconditional T004 acceptance evidence; the qualifying automatic run is authoritative and a forced duplicate is prohibited. **Authority**: Owner-delegated decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9` and DEC-028-006.

## Scope Boundaries

### In scope

- `fastlane/Fastfile` profile-name capture and supported-output diagnostics.
- One real-action Ruby regression under `scripts/tests/`.
- Minimal `scripts/test-repoinfra.sh` wiring that makes the regression mandatory.
- Credential-free verification, exact-candidate review/publication, and post-merge Team Lead evidence collection from the qualifying automatic run.

### Non-goals

- Any `.github/workflows/**`, `project.yml`, generated project, app/package/Prototype, entitlement, bundle-ID, signing-identity, keychain, secret, App Store Connect, or Developer Portal change.
- A Gemfile, dependency-install or version-change step, new third-party dependency, second release lane, workflow trigger change, or automatic retry. The required test gate's assertion against the runner image's existing Fastlane 2.238.0 is in scope and adds no dependency pin.
- Running `fastlane ios beta` or dispatching TestFlight during implementation or planning verification.
- Reopening unrelated `026` generated-project work or `027` automatic-release policy.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The historical current-main implementation fails the new regression because it reads the fabricated convention after both calls.
- **SC-002**: The repaired regression proves two real action invocations, pre-call neutralization of both stale sources, immediate per-call `SIGH_NAME` capture, stale-seeded missing-app and missing-widget target failures, target-correct archive/export mapping, UUID non-use, shell safety, and fail-closed missing/blank/equal behavior without Apple access.
- **SC-003**: On required `macos-26` CI with PATH/RubyGems Fastlane 2.238.0, the focused Ruby regression, the same PATH-selected `ruby -c fastlane/Fastfile`, `bash scripts/test-repoinfra.sh`, and `git diff --check` report success on the exact candidate after the resolver proves CLI/gem/library version agreement.
- **SC-004**: The implementation candidate changes only the three planned RepoInfra paths and preserves all read-only compatibility surfaces.
- **SC-005**: The non-Draft owner-gated PR merges through the normal required checks, then Team Lead records the qualifying automatic TestFlight run for the exact merged head and its uploaded build number on MY-1815 without a duplicate upload.

## Assumptions

- Required `macos-26` CI continues to expose its runner-image RubyGems Fastlane 2.238.0 through matching `fastlane`, `gem`, and Ruby commands on `PATH`. The release host's formula-packaged Fastlane 2.241.0 continues to implement the same conditional `SharedValues::SIGH_NAME` publication contract, but is not the RepoInfra test resolver.
- Profile display names are not secrets but remain opaque data and are not logged by the new tests.
- Owner-delegated decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9` authorizes automatic-run evidence only and explicitly withholds duplicate-upload authority; implementation and planning verification remain credential-free.
