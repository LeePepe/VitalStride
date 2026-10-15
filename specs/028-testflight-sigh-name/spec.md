# Feature Specification: TestFlight per-call SIGH_NAME capture

**Planning version**: MY-1815/v1
**Feature Branch**: `028-testflight-sigh-name`
**Created**: 2026-10-15
**Status**: Ready for revised independent planning review
**Target**: `LeePepe/VitalStride@main`
**Implementation base**: `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`
**Planning lineage**: supersedes reviewed revision `7c5fc64430c2b8dbf6c4216cf7e3203790c45821`
**Authority**: MY-1815 revision 3; Team Lead handoff `01a13e2f-04fa-7e65-b7cd-020c292d187a`; Owner-delegated T004 decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9`; accepted resolve-actual-fastlane decision `01a13f69-fbe2-76ad-aac4-8ff4d0b2c515` and Team Lead handoff `01a13f78-acd2-744f-bbc8-6ff51c847d3a` (2026-10-15)

## Intent

Preserve the TestFlight lane repair already merged at implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`: each target neutralizes both stale Sigh environment state and stale lane-context name state before its real `get_provisioning_profile` call, then captures the profile display name published through `lane_context[SharedValues::SIGH_NAME]` immediately afterward. Revise the merged credential-free regression so it uses the Fastlane toolchain actually selected by unchanged `PATH`, proves one coherent CLI/gem/loaded-library version at or above the documented minimum, and remains fail closed without weakening any real-action, per-call, stale-state, or archive/export assertion. Make that revised regression mandatory in the existing RepoInfra gate.

This revision narrowly supersedes the incorrect profile-name source statements in `specs/026-testflight-profile-reuse/**`. It preserves that feature's valid target-specific signing interface and all behavior accepted by `specs/027-testflight-auto-release/**`.

## Decision Register

- **DEC-028-001 — Supported source**: Fastlane 2.238.0 and 2.241.0 conditionally publish the fetched profile display name as `SharedValues::SIGH_NAME` in lane context when `ENV["SIGH_NAME"]` is present. The action return is the profile UUID, not the name.
- **DEC-028-002 — Fresh per-call provenance**: `ENV["SIGH_NAME"]` and lane-context `SharedValues::SIGH_NAME` are independently stale-capable scalar state because Fastlane publishes a name only when the current call supplies one. Immediately before every real provisioning call, production must neutralize both locations; it must then capture the lane-context name immediately after that call and before any later call.
- **DEC-028-003 — Fail closed**: Missing or blank current-call output, or equal captured target values, terminates with target-specific evidence before `build_app`, upload, distribution, or release-marker mutation. No stale value, return-value, fixed-name, target-copy, or fabricated-env fallback is allowed.
- **DEC-028-004 — Real-action regression**: The regression loads real `fastlane`, `sigh`, and `sigh/manager`, invokes the real provisioning-profile action, and replaces only the external `Sigh::Manager.start` boundary. It may not stub the action or manufacture its return as a display name. Separate missing-app and missing-widget cases deliberately seed stale environment and lane-context values and prove production neutralization defeats both.
- **DEC-028-005 — Narrow compatibility**: The repair changes no workflow, XcodeGen/project setting, signing identity, bundle identifier, build-number, upload/distribution, telemetry, relevance, concurrency, or marker behavior.
- **DEC-028-006 — Delivery and production proof**: Fullstack owns the reviewed RepoInfra candidate and PR. After merge, the qualifying automatic TestFlight `workflow_run` triggered by successful CI on the exact merged `main` head is the authoritative T004 proof. Team Lead records its run/head identity, terminal result, and uploaded build number on MY-1815. No duplicate upload is authorized; a later manual `force=false` run is supplemental only and `force=true` is forbidden for T004.
- **DEC-028-007 — Resolved actual Fastlane toolchain**: The focused regression and mandatory RepoInfra gate resolve `fastlane` from unchanged `PATH` and use the RubyGems toolchain actually selected/provided by that resolved command. They derive one actual Fastlane version, require the CLI, corresponding gem, loaded Fastlane library, and loaded Fastlane/Sigh action sources to agree on that version, and require it to be at least **2.238.0**, the documented minimum known to implement this action contract. Missing Fastlane, an unparseable or below-minimum version, an absent corresponding gem/library, any version/source disagreement, or real-library load failure stops the gate. Dependency installation, PATH mutation/workaround, formula or architecture assumptions, alternate runtime/fallback, workflow edits, skips, and hook bypass are forbidden. This decision supersedes only the exact-2.238.0 executor acceptance in reviewed revision `7c5fc64430c2b8dbf6c4216cf7e3203790c45821`; every per-call, stale-state, real-action, and fail-closed requirement remains.
- **DEC-028-008 — Current-base task boundary**: T001's production repair and broad real-action regression are merged at `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`. T001's former exact-version executor premise is removed. The necessary current-version compatibility adaptation joins T002: T002 may change only `scripts/tests/test_testflight_packaging.rb` and `scripts/test-repoinfra.sh`, while `fastlane/Fastfile` becomes a read-only compatibility surface. T003 verifies and publishes exactly those two paths. This adds no repository, layer, permission, dependency, writer, or implementation approach.

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

**Independent Test**: The Ruby regression resolves the unchanged-PATH Fastlane command and its actual RubyGems toolchain, proves the CLI/gem/loaded-library version is coherent and at least 2.238.0, loads the repository Fastfile and real Fastlane/Sigh libraries, replaces only network/profile-install work at `Sigh::Manager.start`, invokes the real action for app then widget, and observes fresh-call provenance, fail-closed lane behavior, and target-correct build inputs.

**Acceptance Scenarios**:

1. **US2/AC1** — Given two real action invocations publish distinct `SIGH_NAME` and `SIGH_UUID` values, when they complete sequentially, then production clears both stale name locations before each call, lane context exposes each current call's name at that boundary, the second call overwrites shared `SIGH_NAME`, and neither UUID is used as a display name.
2. **US2/AC2** — Given the historical `sigh_<bundle-id>_appstore_profile-name` convention appears as a production read anywhere in `fastlane/**` or `scripts/**`, when the regression runs, then it fails.
3. **US2/AC3** — Given the focused Ruby regression is added, when `bash scripts/test-repoinfra.sh` runs, then that regression is executed through the existing RepoInfra gate with real Fastlane/Sigh loading and no Apple credentials or network call.
4. **US2/AC4** — Given the current automatic-release classifier tests and workflow, when this repair is delivered, then their files and behavior remain unchanged.
5. **US2/AC5** — Given an executor exposes Fastlane through unchanged `PATH`, when the focused test and RepoInfra gate run, then they resolve that command's actual toolchain, require its CLI, corresponding gem, loaded library, and action sources to agree on one version at or above 2.238.0, and report the resolved version; missing Fastlane, an unparseable or below-minimum version, an absent gem/library, a mismatch, or load failure fails the gate instead of skipping, installing, rewriting PATH, or selecting another runtime.

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
- Fastlane is missing from unchanged `PATH`, its resolved version is unparseable or below 2.238.0, or its CLI/gem/loaded-library surfaces disagree: fail the test gate rather than silently skip, install, rewrite PATH, probe a second packaging source, or choose another runtime.

## Requirements

### Functional Requirements

- **FR-001**: The lane MUST retain separate forced, installed App Store profile fetches for `com.leepepe.vitalstride` and `com.leepepe.vitalstride.widgets`.
- **FR-002**: Immediately before the app fetch, the lane MUST neutralize both `ENV["SIGH_NAME"]` and `lane_context[SharedValues::SIGH_NAME]`; immediately after the fetch and before the widget fetch, it MUST capture the current lane-context value as the app profile name.
- **FR-003**: Immediately before the widget fetch, the lane MUST neutralize both `ENV["SIGH_NAME"]` and `lane_context[SharedValues::SIGH_NAME]`; immediately after the fetch, it MUST capture the current lane-context value as the widget profile name.
- **FR-004**: The lane MUST reject a missing or blank current-call name, or non-distinct captured names, with target-specific evidence before `build_app`.
- **FR-005**: The app and widget captured variables MUST remain the sole sources for their matching archive specifier and export bundle mapping.
- **FR-006**: The action return UUID, fixed display names, target-derived `sigh_*_profile-name` keys, and copying one target's name to the other MUST NOT be fallback sources.
- **FR-007**: Profile display names MUST remain shell-safe opaque values and MUST NOT expose credentials, profile contents, certificates, or keychain state.
- **FR-008**: A Ruby regression MUST resolve `fastlane` from unchanged `PATH`, use the actual RubyGems toolchain selected/provided by that command, derive its Fastlane version, require the CLI, corresponding gem, loaded library, and loaded action/Sigh sources to agree on that version, reject any version below the documented minimum 2.238.0, require the real `fastlane`, `sigh`, and `sigh/manager` libraries, and invoke the real `GetProvisioningProfileAction` path without a packaging-source, formula, or architecture-prefix assumption.
- **FR-009**: The regression MAY replace only external build/upload/credential work and `Sigh::Manager.start`; it MUST NOT stub `get_provisioning_profile`, `GetProvisioningProfileAction`, lane context publication, or action return semantics.
- **FR-010**: The regression MUST prove two sequential calls publish distinct names, shared `SIGH_NAME` is per-call/overwritten, UUIDs stay distinct from names, the actual Fastfile lane neutralizes both stale sources before every call, and capture occurs immediately after the matching call.
- **FR-011**: The regression MUST fail for any production read of the fabricated `sigh_<bundle-id>_appstore_profile-name` convention in `fastlane/**` or `scripts/**`.
- **FR-012**: The existing RepoInfra gate MUST execute the Ruby regression exactly once through the same resolve-actual-fastlane contract as the focused check, and MUST fail closed for missing Fastlane, an unparseable or below-2.238.0 version, an absent corresponding gem/library, CLI/gem/loaded-library/source disagreement, or real-library load failure.
- **FR-013**: No existing TestFlight classifier assertion or RepoInfra assertion may be deleted or weakened.
- **FR-014**: `.github/workflows/testflight.yml`, `project.yml`, generated projects, application/package code, and signing/upload/release-state behavior MUST remain unchanged.
- **FR-015**: After merge, Team Lead MUST treat the qualifying automatic TestFlight `workflow_run` for successful CI on the exact merged `main` head as authoritative and record its run URL, source/head identity, terminal result, and uploaded build number on MY-1815.
- **FR-016**: The regression MUST separately pre-seed stale environment and lane-context names for a missing app output and for a missing widget output, and MUST prove target-specific failure at the matching boundary before disallowed downstream work.
- **FR-017**: T004 MUST NOT dispatch `force=true` or any duplicate upload. A manual `force=false` run is supplemental only after the automatic run is terminal and marker-covers the exact merged SHA; it cannot satisfy T004 or substitute for missing/failed automatic proof.

## Existing Behaviour

- Implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8` is the normal merge of T001. Its `fastlane/Fastfile` performs two separate `get_provisioning_profile` calls with `force: true` and `skip_install: false`, neutralizes both stale name locations before each call, captures the matching lane-context name immediately afterward, and preserves the missing/blank/equal guards, shell escaping, and archive/export mapping.
- The merged `scripts/tests/test_testflight_packaging.rb` loads real Fastlane/Sigh and the real Fastfile, replaces only `Sigh::Manager.start` plus unrelated external boundaries, and covers two distinct calls/UUIDs, stale missing-app/widget cases, fabricated-key prohibition, blank/equal failure, shell safety, and export reuse. Its bootstrap incorrectly pins and asserts exactly Fastlane 2.238.0 and assumes independently PATH-selected `fastlane`, `gem`, and Ruby are one toolchain.
- Fastlane 2.238.0/2.241.0's real action reads `ENV["SIGH_NAME"]` from Sigh, writes it to `Actions.lane_context[SharedValues::SIGH_NAME]` only when a name exists, and returns `SIGH_UUID`. Neither Sigh nor the action clears an older environment or lane-context name when the current call supplies none, so both locations can remain stale.
- `project.yml` already maps `VITALSTRIDE_APP_PROFILE_SPECIFIER` and `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` to the correct Release targets. No project change is needed.
- `scripts/tests/test_testflight_freshness.py` covers the automatic-release workflow/classifier but does not exercise Fastlane profile output.
- `scripts/test-repoinfra.sh` at the implementation base does not invoke the Ruby regression. MY-1820's preserved candidate adds one staged invocation, but it has no commit, remote branch, or PR and cannot resume until the revised two-path contract passes planning review.

## Compatibility

- Preserve both bundle identifiers, team ID, forced refresh, installation, Manual Release signing, Apple Distribution identity, base/Debug Automatic signing, and the existing target-specific project keys.
- Preserve missing/blank/equal fail-closed guards, shell escaping, archive/export variable reuse, and failure before upload or marker movement.
- Preserve XcodeGen, build-number calculation, telemetry inputs, App Store Connect API-key handling, upload, internal-group distribution, TestFlight relevance, concurrency, manual compatibility, and marker semantics.
- Preserve every assertion in `scripts/tests/test_testflight_freshness.py` and all unrelated RepoInfra tests.
- Preserve every substantive assertion and real-action boundary in `scripts/tests/test_testflight_packaging.rb`; only its executor/version-resolution contract may change.
- Preserve unchanged-PATH support for the required CI RubyGems Fastlane 2.238.0 and for a coherent installed Fastlane toolchain such as the observed 2.241.0 toolchain, without hard-coding either packaging layout.
- Preserve the path ceiling as one RepoInfra goal and one implementation PR.
- Preserve the automatic post-merge release trigger; do not authorize a duplicate upload or treat a racing/default manual run as authoritative evidence.

## Removed Behaviour

- **RB-001**: Remove all production reads and diagnostic claims for `sigh_<bundle-id>_appstore_profile-name`. **Authority**: DEC-028-001 and MY-1815 diagnosis.
- **RB-002**: Remove delayed app-name resolution after the widget call. Each scalar output is captured at its own call boundary. **Authority**: DEC-028-002.
- **RB-003**: Remove no fail-closed guard and weaken no existing test. **Authority**: DEC-028-003 and DEC-028-005.
- **RB-004**: Remove no workflow, signing, upload, distribution, build-number, telemetry, or release-state behavior. **Authority**: DEC-028-005.
- **RB-005**: Remove the default manual run as unconditional T004 acceptance evidence; the qualifying automatic run is authoritative and a forced duplicate is prohibited. **Authority**: Owner-delegated decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9` and DEC-028-006.
- **RB-006**: Remove the exact-2.238.0 activation/assertion and the premise that independently PATH-selected `fastlane`, `gem`, and Ruby must form the toolchain. Replace them with actual-toolchain resolution, coherent-version proof, and minimum-version enforcement; do not remove or weaken real Fastlane/Sigh loading or any behavioral case. **Authority**: decision `01a13f69-fbe2-76ad-aac4-8ff4d0b2c515` and DEC-028-007.

## Scope Boundaries

### In scope

- Read-only validation that merged `fastlane/Fastfile` behavior remains unchanged and still satisfies the per-call handoff contract.
- Resolver/version-contract adaptation in the existing `scripts/tests/test_testflight_packaging.rb`, with all substantive behavioral coverage preserved.
- Minimal `scripts/test-repoinfra.sh` wiring that makes the revised regression mandatory exactly once.
- Credential-free verification, exact-candidate review/publication, and post-merge Team Lead evidence collection from the qualifying automatic run.

### Non-goals

- Any `.github/workflows/**`, `project.yml`, generated project, app/package/Prototype, entitlement, bundle-ID, signing-identity, keychain, secret, App Store Connect, or Developer Portal change.
- A Gemfile, dependency-install or version-change step, PATH mutation/workaround, new third-party dependency, alternate runtime/fallback, packaging-source probe, second release lane, workflow trigger change, hook bypass, skip, or automatic retry. The 2.238.0 floor is a compatibility minimum, not a dependency pin or exact-version selection.
- Running `fastlane ios beta` or dispatching TestFlight during implementation or planning verification.
- Reopening unrelated `026` generated-project work or `027` automatic-release policy.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The merged T001 implementation at `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8` remains the production baseline: `fastlane/Fastfile` has zero candidate diff and every real-action/per-call/stale-state/fail-closed behavior is revalidated by the revised fixture.
- **SC-002**: The revised regression proves two real action invocations, pre-call neutralization of both stale sources, immediate per-call `SIGH_NAME` capture, stale-seeded missing-app and missing-widget target failures, target-correct archive/export mapping, UUID non-use, shell safety, and fail-closed missing/blank/equal behavior without Apple access.
- **SC-003**: On each supported executor, the focused Ruby regression and `bash scripts/test-repoinfra.sh` report the Fastlane version actually resolved from unchanged `PATH`, prove CLI/gem/loaded-library/source agreement and a version at or above 2.238.0, load real Fastlane/Sigh, and finish successfully; `ruby -c fastlane/Fastfile` and `git diff --check` also succeed.
- **SC-004**: Relative to implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`, the implementation candidate changes exactly `scripts/tests/test_testflight_packaging.rb` and `scripts/test-repoinfra.sh`, with zero diff to `fastlane/Fastfile` and every other compatibility surface.
- **SC-005**: The non-Draft owner-gated PR merges through the normal required checks, then Team Lead records the qualifying automatic TestFlight run for the exact merged head and its uploaded build number on MY-1815 without a duplicate upload.

## Assumptions

- Required `macos-26` CI continues to expose Fastlane 2.238.0 through unchanged `PATH`; other supported executors may expose a newer coherent toolchain. Version 2.238.0 remains the documented minimum because it is the oldest required-runner version whose real action contract was verified; observed 2.241.0 is compatibility evidence, not an exact target or formula-path authority.
- The resolved Fastlane command can identify/use its own RubyGems context even when independently PATH-selected `ruby` or `gem` would not expose that installation. Using the resolved command's actual toolchain is not an alternate runtime; choosing any other toolchain or rewriting PATH is forbidden.
- Profile display names are not secrets but remain opaque data and are not logged by the new tests.
- Owner-delegated decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9` authorizes automatic-run evidence only and explicitly withholds duplicate-upload authority; implementation and planning verification remain credential-free.
