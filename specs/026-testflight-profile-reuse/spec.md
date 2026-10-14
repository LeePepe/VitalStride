# Feature Specification: TestFlight in-run profile reuse

**Feature Branch**: `026-testflight-profile-reuse`

**Created**: 2026-10-13

**Status**: Ready for independent planning review

**Input**: MY-1606 revision 3 at base `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`, plus the MY-1660 Owner recovery decision: make the app and widget archive reuse the App Store profiles fetched during the same release run, reconcile the support-document resource baseline in the AppUI truth source, preserve clean layer-scoped replacement history, add credential-free PR regression coverage, and keep any real TestFlight upload behind explicit Owner consent.

## Decision Register

- **DEC-026-001 — Dynamic profile reuse**: MY-1606 revision 3 and the Team Lead handoff require archive and export to use the two profile names fetched in the same run instead of fixed display names.
- **DEC-026-002 — Compatibility preservation**: MY-1606 revision 3 requires both forced profile refreshes, distinct app/widget profiles, unsigned build compatibility, secret non-disclosure, and the current manual release behavior to remain intact.
- **DEC-026-003 — Owner-controlled production proof**: MY-1606 revision 3 requires explicit Owner consent before a real TestFlight upload. Static and unsigned verification never imply that consent.
- **DEC-026-004 — Fail-closed handoff**: Planning research chooses one two-value handoff from the fetched profile-name outputs to both archive and export. If either output is absent/nil or its validation-only whitespace-stripped view is empty, the release fails before archive or upload rather than using a different fallback source. Validation never replaces the original value with the stripped view: every nonblank name is preserved verbatim.
- **DEC-026-005 — AppUI baseline reconciliation**: The MY-1660 Owner recovery decision authorizes `project.yml` to exclude the support-only `VitalStride/CONTEXT.md` file from the `VitalStride` target resources. This is the baseline-reconciliation component of T001, precedes the two profile-setting substitutions in review evidence, changes no `CONTEXT.md` content, and reaches the generated project only through XcodeGen regeneration.
- **DEC-026-006 — Forward-only replacement**: The MY-1660 Owner recovery decision supersedes PR #441 with a replacement whose immutable source/ancestry base is `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`, created in the preserved delivery workspace on a new branch. The replacement carries separate AppUI and RepoInfra commits; PR #441 and its branch remain unchanged until PR Manager closes it with the published replacement link; no force-push is authorized.
- **DEC-026-007 — Fresh trusted review event**: Shipping the replacement depends independently on MY-1675 / PR #442 first merging through its one-time exact-head human bootstrap. That bypass belongs only to #442 and cannot satisfy MY-1660. T004's trusted event base is the fresh eligible `pull_request_target` event's `github.event.pull_request.base.sha` on default branch `main`, and that revision must contain the merged #442 fix. The event-base advance does not rebase or otherwise change the immutable replacement source base. Replacement publication and the fixed trusted event base converge on a fresh event that must produce a real schema-valid, passing `codex-review-target` result.

## User Scenarios & Testing

### User Story 1 - Archive with the profiles fetched in this run (Priority: P1)

As the release operator, I need the app and widget archive to consume their own profiles fetched during the current run so a runner or valid distribution-certificate change does not require a manual Developer Portal rename or repair.

**Why this priority**: The release currently fetches usable profiles but archives against two older fixed display names, so a certificate change blocks TestFlight before export.

**Independent Test**: A credential-free contract test rejects absent/nil and whitespace-only outputs, then supplies distinct nonblank representative profile names with leading, trailing, and embedded whitespace plus shell-significant characters. It proves the original app value reaches app archive and export verbatim while the original widget value reaches widget archive and export verbatim. An unsigned Release build proves the same configuration remains buildable without profiles or signing credentials.

**Acceptance Scenarios**:

1. **US1/AC1** — **Given** the current release run fetches an app profile named `APP_PROFILE_A` and a widget profile named `WIDGET_PROFILE_B`, **When** the Release archive and export configuration are assembled, **Then** the app uses `APP_PROFILE_A` for both archive and export and the widget uses `WIDGET_PROFILE_B` for both archive and export.
2. **US1/AC2** — **Given** either fetched profile-name output is absent/nil or contains only whitespace, **When** the release reaches the profile handoff, **Then** it terminates before `build_app`, upload, distribution, or release-tag mutation and identifies which target has no usable name without printing credential material.
3. **US1/AC3** — **Given** the two fetched profile names are nonblank but contain leading, trailing, or embedded whitespace or shell-significant characters, **When** they cross the archive and export handoff, **Then** each original complete value is preserved verbatim, reaches only its matching target, and cannot be trimmed, split, interpreted, or swapped.
4. **US1/AC4** — **Given** a pull request has no Apple credentials or installed profiles and signing is explicitly disabled, **When** the Release configuration is generated and built, **Then** the build does not require either dynamic profile value and does not fall back to a fixed profile display name.
5. **US1/AC5** — **Given** `VitalStride/CONTEXT.md` is a support document under the AppUI source root, **When** T001 reconciles the approved base and regenerates the project, **Then** `project.yml` explicitly excludes that file from `VitalStride` target resources, the generated project contains no corresponding file or resource-build reference, and no source or context content is changed.

---

### User Story 2 - Detect signing drift before release (Priority: P1)

As the delivery owner, I need every pull request to check the profile handoff without contacting Apple so archive/export drift is rejected before anyone attempts TestFlight.

**Why this priority**: The defect spans two configuration surfaces and previously survived normal unsigned CI because no test related the fetched names to both archive and export.

**Independent Test**: The existing PR-time repository gate runs static contract coverage against the release lane and XcodeGen source. The newly authored candidate regression is first copied over an isolated archive of the immutable replacement source base and demonstrably fails there for both the historical fixed names and action-return fallback. It then passes on the repaired tree, including cases that reject whitespace-only output while preserving nonblank whitespace-containing values verbatim.

**Acceptance Scenarios**:

1. **US2/AC1** — **Given** a pull request changes release signing configuration, **When** the PR-time repository gate runs, **Then** it verifies two forced installed fetches, two distinct target-specific archive inputs, and reuse of those exact values in export without reading credentials, signing, uploading, or changing Developer Portal state.
2. **US2/AC2** — **Given** the newly authored focused regression is run against an isolated overlay containing the exact immutable-base `project.yml`, `fastlane/Fastfile`, and TestFlight workflow, **When** the regression evaluates that historical state, **Then** it exits nonzero and identifies both the fixed-name configuration and action-return fallback violations; when run against the repaired tree, it separately rejects whitespace-only outputs and accepts nonblank whitespace-containing names only when their original values are preserved verbatim.
3. **US2/AC3** — **Given** the fix is proposed for delivery, **When** the candidate PR is opened, **Then** it is non-Draft, carries the `owner-review` label, documents the new-runner revalidation procedure, and does not claim real-upload evidence.
4. **US2/AC4** — **Given** the implementation has passed exact-revision review and required PR gates but the Owner has not explicitly consented to an upload, **When** delivery reaches production validation, **Then** the real TestFlight workflow remains untriggered and the validation slice remains explicitly blocked on that consent.
5. **US2/AC5** — **Given** the Owner explicitly consents after the reviewed change is available on `main`, **When** the manual TestFlight workflow is triggered, **Then** the build archives with the in-run app/widget profiles, uploads successfully, and reaches Apple processing completion. **Manual evidence**: the consent record, GitHub Actions run URL, and processed TestFlight build identifier; no secret values or signing material are attached.
6. **US2/AC6** — **Given** the replacement still descends from immutable source base `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`, PR #442 has independently merged through its one-time exact-head bootstrap, and default branch `main` now contains that fix, **When** replacement publication and the #442-fixed base converge at T004, **Then** the replacement receives a fresh eligible `pull_request_target` event whose `github.event.pull_request.base.sha` is that fixed `main` revision and records a real schema-valid, passing `codex-review-target` result; neither #442's bypass nor any stale/pre-fix result is accepted.

### Edge Cases

- The app profile resolves while the widget profile does not: fail before archive; do not reuse the app value for the widget.
- The two resolved names happen to be equal: fail the target-distinction contract rather than silently mapping one profile to both bundle identifiers.
- A profile-name output is nil/absent or consists only of whitespace: reject it before `build_app`; never use a fallback.
- A nonblank profile display name contains leading, trailing, or embedded whitespace, quotes, or shell metacharacters: use a stripped view only to determine blankness and preserve the original value verbatim across archive and export.
- The release is skipped because there is no new commit: preserve the existing skip behavior unless the existing `force` input is true.
- A PR runs without a signing certificate, ASC key, profile, or keychain password: static and unsigned checks remain fully runnable.
- The Owner declines or has not yet supplied upload consent: implementation delivery can be reviewed, but US2/AC5 remains blocked and no agent substitutes a dry run for that decision.
- PR #442 is open, unmerged, or merged without the authorized exact-head bootstrap: the replacement may be prepared and reviewed, but its shipping gate remains blocked.
- The replacement has a failing or schema-invalid `codex-review-target` result, a result whose fresh event-base SHA on `main` predates the merged #442 fix, or one from a non-eligible/stale event: discard it as shipping evidence and require a fresh eligible `pull_request_target` event; do not reuse the #442 bypass or alter the immutable replacement source ancestry.

## Requirements

### Functional Requirements

- **FR-001**: The release MUST fetch and install separate App Store profiles for the app and widget bundle identifiers during each release run, retaining `force: true` for both fetches.
- **FR-002**: The release MUST resolve exactly one canonical in-run profile name for each bundle identifier after the fetches and MUST fail before `build_app` when either value is absent/nil, its validation-only whitespace-stripped view is empty, or the preserved raw values are not target-distinct.
- **FR-003**: The app and widget Release configurations MUST each consume a different target-specific dynamic input; neither configuration may contain a fixed provisioning-profile display name.
- **FR-004**: The same resolved app value MUST drive app archive selection and app export mapping, and the same resolved widget value MUST drive widget archive selection and widget export mapping.
- **FR-005**: Every nonblank profile-name value, including one with leading, trailing, or embedded whitespace or shell-significant characters, MUST cross archive and export as the original verbatim opaque value through shell-safe target-specific transport; blankness validation MUST NOT trim or otherwise mutate the transported value. Credential values MUST NOT be included in that interface, logs, tests, or planning artifacts.
- **FR-006**: Release signing MUST remain manual with the Apple Distribution identity, while the base/Debug configuration remains Automatic.
- **FR-007**: Explicitly unsigned Release builds MUST remain possible with no dynamic profile values, credentials, installed profiles, or network access.
- **FR-008**: A credential-free static regression MUST cover FR-001 through FR-007, including distinct red-capable cases for absent/nil, whitespace-only, nonblank whitespace-containing, historical fixed-name, and action-return-fallback behavior; it MUST be auto-discovered by the existing PR-time repository validation path and MUST be demonstrably red against the isolated immutable-base overlay before it is green on the repaired tree.
- **FR-009**: The workflow MUST preserve manual-only dispatch, `force=false` by default, force-or-new-commit gating, `main` checkout, non-cancelling release concurrency, current build-number behavior, upload/distribution behavior, and release-tag mutation semantics.
- **FR-010**: No real TestFlight lane or equivalent workflow dispatch may be used as implementation or review verification before explicit Owner consent.
- **FR-011**: The implementation PR MUST be non-Draft, MUST carry `owner-review`, and MUST describe the manual new-runner validation steps and the Owner-consent prerequisite.
- **FR-012**: After explicit Owner consent and merge to `main`, the manual validation MUST record that the uploaded build reached Apple processing completion without exposing ASC keys, certificate data, keychain passwords, or provisioning-profile contents.
- **FR-013**: T001 MUST add the `VitalStride/CONTEXT.md` target-resource exclusion to `project.yml` as an explicit baseline-reconciliation truth-source edit, MUST synchronize it through XcodeGen, and MUST NOT edit the support document or hand-edit `VitalStride.xcodeproj/**`.
- **FR-014**: Recovery implementation MUST use `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` as its immutable replacement source/ancestry base in the preserved delivery workspace on a new branch, MUST publish separate AppUI and RepoInfra commits, MUST leave PR #441 unchanged until the replacement is published and linked for closure, and MUST NOT force-push or substitute a later trusted event base for that ancestry.
- **FR-015**: Replacement shipping MUST remain blocked until the independently progressing PR #442 merges through its one-time exact-head human bootstrap and a fresh eligible `pull_request_target` event targets a `main` base revision containing that fix. T004 MUST join that trusted event-base prerequisite with replacement publication and MUST record a real schema-valid, passing `codex-review-target` result for the replacement head without reusing the #442 bypass or rebasing the replacement away from its immutable source base.

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
- **RB-002**: Remove export fallback from an absent/nil or whitespace-only canonical profile-name output to the provisioning action's return value; any such unusable output now fails closed before `build_app`. **Authority**: DEC-026-004.
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

- **SC-001**: The focused credential-free regression rejects absent/nil and whitespace-only outputs, preserves nonblank whitespace-containing values verbatim through both archive and export, and produces captured nonzero evidence against an isolated immutable-base overlay identifying both the historical fixed-name configuration and action-return fallback before it passes on the repaired tree.
- **SC-002**: The complete RepoInfra gate finishes with zero failures and runs the new regression on the PR path.
- **SC-003**: XcodeGen regeneration is synchronized and an unsigned generic-iOS Release build completes with no Apple credentials or profiles.
- **SC-004**: Required PR checks are green on a non-Draft `owner-review` candidate; CI state is shipping evidence owned by PR Manager, not an AI Reviewer content verdict.
- **SC-005**: Only after explicit Owner consent, one manual TestFlight run on `main` reaches Apple processing completion using the two profiles fetched in that run.
- **SC-006**: XcodeGen regeneration from the authorized three-edit AppUI truth source excludes `VitalStride/CONTEXT.md`, applies only the two target-specific profile substitutions beyond that baseline reconciliation, and is idempotent under the same installed XcodeGen executable.
- **SC-007**: Without changing the replacement's `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` ancestry, the published replacement records a fresh, real, schema-valid, passing `codex-review-target` result from an eligible `pull_request_target` event whose `github.event.pull_request.base.sha` is a `main` revision containing the merged PR #442 fix; no bypass or pre-fix result is used.

## Assumptions

- The existing canonical in-run profile-name outputs remain the supported source of profile display names for the installed Fastlane version.
- Profile display names are not secrets, but they are treated as opaque untrusted shell values.
- A real TestFlight run can mutate Developer Portal profile state and publish a build, so DEC-026-003 is an external authorization gate rather than an implementation command.
- The PR #442 bootstrap is a one-time human action scoped to that exact head; its merge changes the trusted review control plane but grants no bypass authority to the MY-1660 replacement.
- The repository's existing required PR checks remain the authoritative CI gates; this feature adds no new workflow or check identity.
