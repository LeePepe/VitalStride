# Feature Specification: TestFlight per-call SIGH_NAME capture

**Planning version**: MY-1815/v1
**Feature Branch**: `028-testflight-sigh-name`
**Created**: 2026-10-15
**Status**: Ready for independent planning review
**Target**: `LeePepe/VitalStride@main`
**Product base**: `663054cb4e7f58459fd0caf6a0710f6e74f18bd0`
**Authority**: MY-1815 revision 3 and Team Lead handoff `01a13e2f-04fa-7e65-b7cd-020c292d187a`

## Intent

Repair the TestFlight lane so each target captures the profile display name that Fastlane publishes through `lane_context[SharedValues::SIGH_NAME]` immediately after that target's `get_provisioning_profile` call. Preserve the existing fail-closed checks and app/widget archive-export mapping. Add a credential-free regression that loads the real Fastlane/Sigh action and rejects the fabricated target-derived environment-key convention.

This revision narrowly supersedes the incorrect profile-name source statements in `specs/026-testflight-profile-reuse/**`. It preserves that feature's valid target-specific signing interface and all behavior accepted by `specs/027-testflight-auto-release/**`.

## Decision Register

- **DEC-028-001 — Supported source**: Fastlane 2.241.0 publishes the fetched profile display name as `SharedValues::SIGH_NAME` in lane context. The action return is the profile UUID, not the name.
- **DEC-028-002 — Per-call capture**: `SIGH_NAME` is scalar shared state overwritten by each provisioning call. The app value must be captured after the app call and before the widget call; the widget value must be captured immediately after the widget call.
- **DEC-028-003 — Fail closed**: Missing, blank, or equal captured values terminate before `build_app`, upload, distribution, or release-marker mutation. No return-value, fixed-name, target-copy, or fabricated-env fallback is allowed.
- **DEC-028-004 — Real-action regression**: The regression loads real `fastlane`, `sigh`, and `sigh/manager`, invokes the real provisioning-profile action, and replaces only the external `Sigh::Manager.start` boundary. It may not stub the action or manufacture its return as a display name.
- **DEC-028-005 — Narrow compatibility**: The repair changes no workflow, XcodeGen/project setting, signing identity, bundle identifier, build-number, upload/distribution, telemetry, relevance, concurrency, or marker behavior.
- **DEC-028-006 — Delivery and production proof**: Fullstack owns the reviewed RepoInfra candidate and PR. After merge, Team Lead reruns the existing manual TestFlight workflow on `main` and records the uploaded build number on MY-1815.

## User Scenarios & Testing

### User Story 1 - Archive with each profile fetched in this run (Priority: P1)

As the release operator, I need the app and widget to use the display names returned by their own current-run profile fetches so the archive can proceed without relying on a nonexistent environment-key convention.

**Independent Test**: A credential-free fixture drives the real Fastlane provisioning action twice with distinct names and UUIDs, then proves the actual lane captures the first name before the second call overwrites shared state and maps both names to the correct archive and export targets.

**Acceptance Scenarios**:

1. **US1/AC1** — Given the app fetch publishes `APP_PROFILE_A`, when the widget fetch begins, then the lane has already captured `APP_PROFILE_A` for the app.
2. **US1/AC2** — Given the widget fetch publishes `WIDGET_PROFILE_B`, when the lane assembles archive and export configuration, then the widget uses `WIDGET_PROFILE_B` and the app still uses `APP_PROFILE_A`.
3. **US1/AC3** — Given either call publishes no name or a blank name, when the lane validates the handoff, then it terminates before archive, upload, distribution, or marker mutation and identifies the affected target without exposing credentials or profile contents.
4. **US1/AC4** — Given both calls publish the same display name, when the lane validates target distinction, then it terminates before archive instead of mapping one profile to both bundle identifiers.
5. **US1/AC5** — Given a profile name contains spaces or shell-significant characters, when the lane passes archive inputs, then the complete value remains opaque, shell-safe, and target-correct, and export reuses the same captured variable.

### User Story 2 - Reject profile-output drift before release (Priority: P1)

As the delivery owner, I need the repository gate to exercise Fastlane's real output contract without Apple access so a fabricated key, action stub, UUID fallback, or delayed capture cannot reach the release runner.

**Independent Test**: The Ruby regression loads the repository Fastfile and the installed Fastlane/Sigh libraries, stubs only network/profile-install work at `Sigh::Manager.start`, invokes the real action for app then widget, and observes fail-closed lane behavior and target-correct build inputs.

**Acceptance Scenarios**:

1. **US2/AC1** — Given two real action invocations publish distinct `SIGH_NAME` and `SIGH_UUID` values, when they complete sequentially, then lane context exposes each call's name at that call boundary, the second call overwrites shared `SIGH_NAME`, and neither UUID is used as a display name.
2. **US2/AC2** — Given the historical `sigh_<bundle-id>_appstore_profile-name` convention appears as a production read anywhere in `fastlane/**` or `scripts/**`, when the regression runs, then it fails.
3. **US2/AC3** — Given the focused Ruby regression is added, when `bash scripts/test-repoinfra.sh` runs, then that regression is executed through the existing RepoInfra gate with real Fastlane/Sigh loading and no Apple credentials or network call.
4. **US2/AC4** — Given the current automatic-release classifier tests and workflow, when this repair is delivered, then their files and behavior remain unchanged.

### User Story 3 - Confirm the repaired path in TestFlight (Priority: P1)

As the delivery lead, I need one post-merge manual run from `main` to confirm the repaired signing handoff uploads a build successfully.

**Independent Test**: After the reviewed PR merges, Team Lead runs the existing TestFlight workflow on `main` and records the Actions run URL, terminal result, and uploaded build number on MY-1815.

**Acceptance Scenarios**:

1. **US3/AC1** — Given the reviewed repair is merged to `main`, when Team Lead runs the existing manual workflow, then it uses the unchanged release policy and the repaired per-call names.
2. **US3/AC2** — Given the run succeeds, when evidence is recorded, then MY-1815 contains the run URL and uploaded build number without credential, certificate, keychain, or profile contents.
3. **US3/AC3** — Given the run fails, when evidence is recorded, then the issue remains open with the exact failing step and no false completion claim.

### Edge Cases

- The app call succeeds but publishes no usable name: fail before the widget value can mask the app failure.
- The widget call overwrites shared context: preserve the already captured app name.
- The action returns a UUID while publishing a different display name: use only the display name.
- A prior lane run left `SIGH_NAME` populated: clear fixture state and prove each invocation supplies its own value.
- A contributor retains the fabricated convention only in an error message: replace it with supported-output wording so repository-wide regression checks do not normalize the invalid contract.
- Fastlane/Sigh is unavailable to the repository gate: fail the test gate rather than silently skip the real-action regression.

## Requirements

### Functional Requirements

- **FR-001**: The lane MUST retain separate forced, installed App Store profile fetches for `com.leepepe.vitalstride` and `com.leepepe.vitalstride.widgets`.
- **FR-002**: Immediately after the app fetch and before the widget fetch, the lane MUST capture `lane_context[SharedValues::SIGH_NAME]` as the app profile name.
- **FR-003**: Immediately after the widget fetch, the lane MUST capture `lane_context[SharedValues::SIGH_NAME]` as the widget profile name.
- **FR-004**: The lane MUST reject a missing, blank, or non-distinct captured name before `build_app`.
- **FR-005**: The app and widget captured variables MUST remain the sole sources for their matching archive specifier and export bundle mapping.
- **FR-006**: The action return UUID, fixed display names, target-derived `sigh_*_profile-name` keys, and copying one target's name to the other MUST NOT be fallback sources.
- **FR-007**: Profile display names MUST remain shell-safe opaque values and MUST NOT expose credentials, profile contents, certificates, or keychain state.
- **FR-008**: A Ruby regression MUST require the installed real `fastlane`, `sigh`, and `sigh/manager` libraries and invoke the real `GetProvisioningProfileAction` path.
- **FR-009**: The regression MAY replace only external build/upload/credential work and `Sigh::Manager.start`; it MUST NOT stub `get_provisioning_profile`, `GetProvisioningProfileAction`, lane context publication, or action return semantics.
- **FR-010**: The regression MUST prove two sequential calls publish distinct names, shared `SIGH_NAME` is per-call/overwritten, UUIDs stay distinct from names, and the actual Fastfile lane captures before overwrite.
- **FR-011**: The regression MUST fail for any production read of the fabricated `sigh_<bundle-id>_appstore_profile-name` convention in `fastlane/**` or `scripts/**`.
- **FR-012**: The existing RepoInfra gate MUST execute the Ruby regression and fail closed when the real Fastlane/Sigh runtime cannot be loaded.
- **FR-013**: No existing TestFlight classifier assertion or RepoInfra assertion may be deleted or weakened.
- **FR-014**: `.github/workflows/testflight.yml`, `project.yml`, generated projects, application/package code, and signing/upload/release-state behavior MUST remain unchanged.
- **FR-015**: After merge, Team Lead MUST run the existing manual TestFlight workflow on `main` and record the run URL, terminal result, and uploaded build number on MY-1815.

## Existing Behaviour

- `fastlane/Fastfile` performs two separate `get_provisioning_profile` calls with `force: true` and `skip_install: false`, first for the app and then for the widget.
- After both calls, the lane reads two target-derived lowercase environment keys that Fastlane's Sigh action never publishes. Both values are therefore nil and the current guard aborts before archive.
- Fastlane 2.241.0's real action reads `ENV["SIGH_NAME"]` from Sigh, writes it to `Actions.lane_context[SharedValues::SIGH_NAME]`, and returns `SIGH_UUID`. Each call overwrites the scalar shared name.
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

## Removed Behaviour

- **RB-001**: Remove all production reads and diagnostic claims for `sigh_<bundle-id>_appstore_profile-name`. **Authority**: DEC-028-001 and MY-1815 diagnosis.
- **RB-002**: Remove delayed app-name resolution after the widget call. Each scalar output is captured at its own call boundary. **Authority**: DEC-028-002.
- **RB-003**: Remove no fail-closed guard and weaken no existing test. **Authority**: DEC-028-003 and DEC-028-005.
- **RB-004**: Remove no workflow, signing, upload, distribution, build-number, telemetry, or release-state behavior. **Authority**: DEC-028-005.

## Scope Boundaries

### In scope

- `fastlane/Fastfile` profile-name capture and supported-output diagnostics.
- One real-action Ruby regression under `scripts/tests/`.
- Minimal `scripts/test-repoinfra.sh` wiring that makes the regression mandatory.
- Credential-free verification, exact-candidate review/publication, and post-merge Team Lead production proof.

### Non-goals

- Any `.github/workflows/**`, `project.yml`, generated project, app/package/Prototype, entitlement, bundle-ID, signing-identity, keychain, secret, App Store Connect, or Developer Portal change.
- A Fastlane version pin, Gemfile, new third-party dependency, second release lane, workflow trigger change, or automatic retry.
- Running `fastlane ios beta` or dispatching TestFlight during implementation or planning verification.
- Reopening unrelated `026` generated-project work or `027` automatic-release policy.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The historical current-main implementation fails the new regression because it reads the fabricated convention after both calls.
- **SC-002**: The repaired regression proves two real action invocations, per-call `SIGH_NAME` capture, target-correct archive/export mapping, UUID non-use, shell safety, and fail-closed missing/blank/equal behavior without Apple access.
- **SC-003**: The focused Ruby regression, `ruby -c fastlane/Fastfile`, `bash scripts/test-repoinfra.sh`, and `git diff --check` report success on the exact candidate in an environment that provides the repository's supported Fastlane runtime.
- **SC-004**: The implementation candidate changes only the three planned RepoInfra paths and preserves all read-only compatibility surfaces.
- **SC-005**: The non-Draft owner-gated PR merges through the normal required checks, then Team Lead records a successful manual TestFlight run and uploaded build number on MY-1815.

## Assumptions

- The release environment continues to provide Homebrew Fastlane 2.241.0 or a compatible version with the documented `SharedValues::SIGH_NAME` contract.
- Profile display names are not secrets but remain opaque data and are not logged by the new tests.
- The issue itself authorizes the post-merge Team Lead rerun; implementation and planning verification remain credential-free.
