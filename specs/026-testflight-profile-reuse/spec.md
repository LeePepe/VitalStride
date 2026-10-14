# Feature Specification: TestFlight in-run profile reuse

**Feature Branch**: `026-testflight-profile-reuse`

**Created**: 2026-10-13

**Status**: Ready for independent planning review

**Input**: MY-1606 revision 3 at base `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`, plus the MY-1660 Owner recovery decision: make the app and widget archive reuse the App Store profiles fetched during the same release run, reconcile the support-document resource baseline in the AppUI truth source, preserve clean layer-scoped replacement history, add credential-free PR regression coverage, and keep any real TestFlight upload behind explicit Owner consent.

## Decision Register

- **DEC-026-001 — Dynamic profile reuse**: MY-1606 revision 3 and the Team Lead handoff require archive and export to use the two profile names fetched in the same run instead of fixed display names.
- **DEC-026-002 — Compatibility preservation**: MY-1606 revision 3 requires both forced profile refreshes, distinct app/widget profiles, unsigned build compatibility, secret non-disclosure, and the current manual release behavior to remain intact.
- **DEC-026-003 — Owner-controlled production proof**: MY-1606 revision 3 requires explicit Owner consent before a real TestFlight upload. Static and unsigned verification never imply that consent.
- **DEC-026-004 — Fail-closed handoff**: Planning research chooses one two-value handoff from the fetched profile-name outputs to both archive and export. If either output is absent, the release fails before archive or upload rather than using a different fallback source.
- **DEC-026-005 — AppUI baseline reconciliation**: The MY-1660 Owner recovery decision authorizes `project.yml` to exclude the support-only `VitalStride/CONTEXT.md` file from the `VitalStride` target resources. This is the baseline-reconciliation component of T001, precedes the two profile-setting substitutions in review evidence, changes no `CONTEXT.md` content, and reaches the generated project only through XcodeGen regeneration.
- **DEC-026-006 — Forward-only replacement**: The MY-1660 Owner recovery decision supersedes PR #441 with a replacement starting from `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` in the preserved delivery workspace on a new branch. The replacement carries separate AppUI and RepoInfra commits; PR #441 and its branch remain unchanged until PR Manager closes it with the published replacement link; no force-push is authorized.
- **DEC-026-007 — Fresh trusted review event**: Shipping the replacement depends on MY-1675 / PR #442 first merging through its one-time exact-head human bootstrap. That bypass belongs only to #442 and cannot satisfy MY-1660. After the trusted base contains the #442 fix, the replacement must receive a fresh eligible `pull_request_target` event and a real schema-valid, passing `codex-review-target` result.

## User Scenarios & Testing

### User Story 1 - Archive with the profiles fetched in this run (Priority: P1)

As the release operator, I need the app and widget archive to consume their own profiles fetched during the current run so a runner or valid distribution-certificate change does not require a manual Developer Portal rename or repair.

**Why this priority**: The release currently fetches usable profiles but archives against two older fixed display names, so a certificate change blocks TestFlight before export.

**Independent Test**: A credential-free contract test supplies two distinct representative profile names, including whitespace, and proves the app archive input and app export mapping use the app value while the widget archive input and widget export mapping use the widget value. An unsigned Release build proves the same configuration remains buildable without profiles or signing credentials.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** the current release run fetches an app profile named `APP_PROFILE_A` and a widget profile named `WIDGET_PROFILE_B`, **When** the Release archive and export configuration are assembled, **Then** the app uses `APP_PROFILE_A` for both archive and export and the widget uses `WIDGET_PROFILE_B` for both archive and export.
2. **US1/AC2** — **Given** either fetched profile-name output is missing or empty, **When** the release reaches the profile handoff, **Then** it terminates before archive, upload, distribution, or release-tag mutation and identifies which target has no usable name without printing credential material.
3. **US1/AC3** — **Given** the two fetched profile names contain whitespace or shell-significant characters, **When** they cross the archive handoff, **Then** each complete value reaches only its matching target and cannot be split, interpreted, or swapped.
4. **US1/AC4** — **Given** a pull request has no Apple credentials or installed profiles and signing is explicitly disabled, **When** the Release configuration is generated and built, **Then** the build does not require either dynamic profile value and does not fall back to a fixed profile display name.
5. **US1/AC5** — **Given** `VitalStride/CONTEXT.md` is a support document under the AppUI source root, **When** T001 reconciles the approved base and regenerates the project, **Then** `project.yml` explicitly excludes that file from `VitalStride` target resources, the generated project contains no corresponding file or resource-build reference, and no source or context content is changed.

---

### User Story 2 - Detect signing drift before release (Priority: P1)

As the delivery owner, I need every pull request to check the profile handoff without contacting Apple so archive/export drift is rejected before anyone attempts TestFlight.

**Why this priority**: The defect spans two configuration surfaces and previously survived normal unsigned CI because no test related the fetched names to both archive and export.

**Independent Test**: The existing PR-time repository gate runs static contract coverage against the release lane and XcodeGen source. The test fails if either fixed name returns, either forced fetch is weakened, target values are crossed, archive/export use different sources, or the release lane restores the action-return fallback.

**Acceptance Scenarios**:

1. **US2/AC1** — **Given** a pull request changes release signing configuration, **When** the PR-time repository gate runs, **Then** it verifies two forced installed fetches, two distinct target-specific archive inputs, and reuse of those exact values in export without reading credentials, signing, uploading, or changing Developer Portal state.
2. **US2/AC2** — **Given** a contributor reintroduces either historical fixed display name or makes archive and export consume different sources, **When** the focused regression runs, **Then** the regression fails with the violated app or widget contract identified.
3. **US2/AC3** — **Given** the fix is proposed for delivery, **When** the candidate PR is opened, **Then** it is non-Draft, carries the `owner-review` label, documents the new-runner revalidation procedure, and does not claim real-upload evidence.
4. **US2/AC4** — **Given** the implementation has passed exact-revision review and required PR gates but the Owner has not explicitly consented to an upload, **When** delivery reaches production validation, **Then** the real TestFlight workflow remains untriggered and the validation slice remains explicitly blocked on that consent.
5. **US2/AC5** — **Given** the Owner explicitly consents after the reviewed change is available on `main`, **When** the manual TestFlight workflow is triggered, **Then** the build archives with the in-run app/widget profiles, uploads successfully, and reaches Apple processing completion. **Manual evidence**: the consent record, GitHub Actions run URL, and processed TestFlight build identifier; no secret values or signing material are attached.
6. **US2/AC6** — **Given** PR #442 has merged through its one-time exact-head bootstrap and the trusted base now contains the MY-1675 fix, **When** the MY-1660 replacement is evaluated for shipping, **Then** it receives a fresh eligible `pull_request_target` event and records a real schema-valid, passing `codex-review-target` result; neither #442's bypass nor any stale/pre-fix result is accepted.

### Edge Cases

- The app profile resolves while the widget profile does not: fail before archive; do not reuse the app value for the widget.
- The two resolved names happen to be equal: fail the target-distinction contract rather than silently mapping one profile to both bundle identifiers.
- A profile display name contains spaces, quotes, or shell metacharacters: preserve it as opaque data across the archive handoff.
- The release is skipped because there is no new commit: preserve the existing skip behavior unless the existing `force` input is true.
- A PR runs without a signing certificate, ASC key, profile, or keychain password: static and unsigned checks remain fully runnable.
- The Owner declines or has not yet supplied upload consent: implementation delivery can be reviewed, but US2/AC5 remains blocked and no agent substitutes a dry run for that decision.
- PR #442 is open, unmerged, or merged without the authorized exact-head bootstrap: the replacement may be prepared and reviewed, but its shipping gate remains blocked.
- The replacement has a failing or schema-invalid `codex-review-target` result, a result created before the trusted base contains the #442 fix, or one from a non-eligible/stale event: discard it as shipping evidence and require a fresh eligible `pull_request_target` event; do not reuse the #442 bypass.

## Requirements

### Functional Requirements

- **FR-001**: The release MUST fetch and install separate App Store profiles for the app and widget bundle identifiers during each release run, retaining `force: true` for both fetches.
- **FR-002**: The release MUST resolve exactly one canonical in-run profile name for each bundle identifier after the fetches and MUST fail before archive when either value is absent, empty, or not target-distinct.
- **FR-003**: The app and widget Release configurations MUST each consume a different target-specific dynamic input; neither configuration may contain a fixed provisioning-profile display name.
- **FR-004**: The same resolved app value MUST drive app archive selection and app export mapping, and the same resolved widget value MUST drive widget archive selection and widget export mapping.
- **FR-005**: Profile-name values MUST cross the archive interface as opaque shell-safe values; credential values MUST NOT be included in that interface, logs, tests, or planning artifacts.
- **FR-006**: Release signing MUST remain manual with the Apple Distribution identity, while the base/Debug configuration remains Automatic.
- **FR-007**: Explicitly unsigned Release builds MUST remain possible with no dynamic profile values, credentials, installed profiles, or network access.
- **FR-008**: A credential-free static regression MUST cover FR-001 through FR-007 and MUST be auto-discovered by the existing PR-time repository validation path.
- **FR-009**: The workflow MUST preserve manual-only dispatch, `force=false` by default, force-or-new-commit gating, `main` checkout, non-cancelling release concurrency, current build-number behavior, upload/distribution behavior, and release-tag mutation semantics.
- **FR-010**: No real TestFlight lane or equivalent workflow dispatch may be used as implementation or review verification before explicit Owner consent.
- **FR-011**: The implementation PR MUST be non-Draft, MUST carry `owner-review`, and MUST describe the manual new-runner validation steps and the Owner-consent prerequisite.
- **FR-012**: After explicit Owner consent and merge to `main`, the manual validation MUST record that the uploaded build reached Apple processing completion without exposing ASC keys, certificate data, keychain passwords, or provisioning-profile contents.
- **FR-013**: T001 MUST add the `VitalStride/CONTEXT.md` target-resource exclusion to `project.yml` as an explicit baseline-reconciliation truth-source edit, MUST synchronize it through XcodeGen, and MUST NOT edit the support document or hand-edit `VitalStride.xcodeproj/**`.
- **FR-014**: Recovery implementation MUST start from `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` in the preserved delivery workspace on a new branch, MUST publish separate AppUI and RepoInfra commits, MUST leave PR #441 unchanged until the replacement is published and linked for closure, and MUST NOT force-push.
- **FR-015**: Replacement shipping MUST remain blocked until PR #442 merges through its one-time exact-head human bootstrap; after that fix exists in the trusted base, MY-1660 MUST obtain a fresh eligible `pull_request_target` event and a real schema-valid, passing `codex-review-target` result without reusing the #442 bypass.

## Existing Behaviour

- The manual TestFlight workflow checks out `main`, skips when there is no new commit unless `force=true`, and invokes one release lane.
- The lane regenerates the Xcode project, computes a globally monotonic build number, and fetches/installs separate app and widget App Store profiles with forced refresh.
- Export mapping reads in-run profile-name outputs, but archive selection still reads fixed app and widget display names from Release project configuration. A new profile with a timestamp suffix therefore works for export but cannot be selected for archive.
- At the approved base, the `VitalStride` source entry in `project.yml` does not exclude `VitalStride/CONTEXT.md`; XcodeGen can therefore add this support-only document to app-target resources. Correcting that truth-source omission is baseline reconciliation, not a product or domain-context change.
- Debug inherits Automatic signing. Pull-request CI regenerates the project and performs credential-free simulator and repository checks.

## Compatibility

- Preserve both forced installed profile fetches and keep the app/widget bundle identifiers distinct.
- Preserve manual Release signing, Apple Distribution identity, base/Debug Automatic signing, and credential-free unsigned Release builds.
- Preserve all release freshness, `force`, build-number, telemetry-setting, upload, internal-group distribution, and release-tag behavior.
- Preserve secret handling: ASC key material remains environment-provided and is never written into the repository, logs, fixtures, or generated planning evidence.
- Preserve existing TestFlight freshness regression coverage; strengthen it without deleting or weakening an assertion.
- Preserve `VitalStride/CONTEXT.md` as an unchanged support document while excluding it from app-target resources; generated-project synchronization does not give the file or generated output new layer ownership.
- Preserve layer ownership and reviewable history: T001 produces the AppUI commit, T002 produces the RepoInfra commit, and integration/shipping proof produces no source commit.
- Preserve PR #441 unchanged until the replacement is published, then let PR Manager close it with the replacement link; no history rewrite or force-push is permitted.
- Preserve PR-required delivery: implementation reaches `main` only through a non-Draft reviewed PR and the required checks in Constitution §Development Workflow.

## Removed Behaviour

- **RB-001**: Remove archive-time reliance on the fixed app profile display name and fixed widget profile display name. **Authority**: DEC-026-001.
- **RB-002**: Remove export fallback from a missing canonical profile-name output to the provisioning action's return value; missing canonical output now fails closed before archive. **Authority**: DEC-026-004.
- **RB-003**: Remove no tests and weaken no existing assertion. Any proposed test deletion or release-gate weakening is outside this specification and requires a new decision. **Authority**: DEC-026-002.
- **RB-004**: Remove `VitalStride/CONTEXT.md` from the generated `VitalStride` target file/resource membership without deleting or editing the support document. **Authority**: DEC-026-005.

## Scope Boundaries

### In scope

- The XcodeGen Release-signing handoff for the iOS app and widget targets.
- The Fastlane profile-name resolution, archive injection, and export mapping.
- Credential-free static regression coverage through the existing PR repository gate.
- Generated Xcode project synchronization required by Constitution Principle IV.
- The AppUI baseline-reconciliation edit that excludes `VitalStride/CONTEXT.md` from target resources before the two profile-setting substitutions are evaluated.
- Non-Draft PR instructions and the separate Owner-controlled TestFlight validation evidence.
- Forward-only replacement delivery and the MY-1675 / PR #442 shipping dependency.

### Non-goals

- Modifying, renaming, or revoking any existing Developer Portal profile or certificate.
- Revoking certificate `JQ4PB6PGHL` or changing team `4Z8GG667QD`.
- Automating TestFlight publication or changing the manual workflow trigger.
- Changing AIDash or any repository other than VitalStride.
- Changing application source, packages, entitlements, bundle identifiers, marketing/build-number policy, telemetry behavior, upload/distribution behavior, or release-tag policy.
- Editing `VitalStride/CONTEXT.md`, hand-editing the generated Xcode project, rewriting PR #441, force-pushing, or treating the #442 bootstrap bypass as reusable authorization.
- Storing or printing ASC keys, certificate contents, keychain passwords, `.p8` files, or `.mobileprovision` contents.

## Success Criteria

### Measurable Outcomes

- **SC-001**: The focused credential-free regression proves both target-specific fetched names feed both archive and export and fails for the historical fixed-name configuration.
- **SC-002**: The complete RepoInfra gate finishes with zero failures and runs the new regression on the PR path.
- **SC-003**: XcodeGen regeneration is synchronized and an unsigned generic-iOS Release build completes with no Apple credentials or profiles.
- **SC-004**: Required PR checks are green on a non-Draft `owner-review` candidate; CI state is shipping evidence owned by PR Manager, not an AI Reviewer content verdict.
- **SC-005**: Only after explicit Owner consent, one manual TestFlight run on `main` reaches Apple processing completion using the two profiles fetched in that run.
- **SC-006**: XcodeGen regeneration from the authorized three-edit AppUI truth source excludes `VitalStride/CONTEXT.md`, applies only the two target-specific profile substitutions beyond that baseline reconciliation, and is idempotent under the same installed XcodeGen executable.
- **SC-007**: The replacement records a fresh, real, schema-valid, passing `codex-review-target` result from an eligible `pull_request_target` event after the trusted base contains the merged PR #442 fix; no bypass or pre-fix result is used.

## Assumptions

- The existing canonical in-run profile-name outputs remain the supported source of profile display names for the installed Fastlane version.
- Profile display names are not secrets, but they are treated as opaque untrusted shell values.
- A real TestFlight run can mutate Developer Portal profile state and publish a build, so DEC-026-003 is an external authorization gate rather than an implementation command.
- The PR #442 bootstrap is a one-time human action scoped to that exact head; its merge changes the trusted review control plane but grants no bypass authority to the MY-1660 replacement.
- The repository's existing required PR checks remain the authoritative CI gates; this feature adds no new workflow or check identity.
