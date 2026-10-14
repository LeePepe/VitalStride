# State Model: TestFlight profile handoff

No product entity, persisted schema, or user data changes. The relevant model is ephemeral release state.

## AppUI Configuration States

1. **Approved base**: `project.yml` still permits `VitalStride/CONTEXT.md` to enter `VitalStride` target resources and still contains two fixed Release profile display names.
2. **Baseline reconciled**: T001 adds the `CONTEXT.md` source exclusion in `project.yml`; the support document remains unchanged and XcodeGen removes its generated file/resource references.
3. **Signing seam configured**: in the same AppUI task and commit, the app and widget fixed profile settings are replaced by their distinct target-specific interface keys.
4. **Generated evidence synchronized**: XcodeGen regeneration contains the baseline exclusion and two profile substitutions without unrelated drift; a second run with the same recorded executable leaves the generated project unchanged.

## Values

- **App fetched profile name**: opaque display name published by the app bundle's forced fetch.
- **Widget fetched profile name**: opaque display name published by the widget bundle's forced fetch.
- **App archive input**: the app fetched name after validation and shell-safe transport.
- **Widget archive input**: the widget fetched name after validation and shell-safe transport.
- **Export mapping**: bundle identifier to the same validated value used by its archive input.

## Release States

1. **Profiles requested**: both target-specific forced fetches are invoked with installation enabled.
2. **Profiles resolved**: both canonical profile-name outputs exist, are non-empty, and are target-distinct.
3. **Archive configured**: both opaque values are attached to their matching target-specific build-setting keys.
4. **Archive completed**: the signed archive succeeds with those values.
5. **Export completed**: export maps each bundle identifier to the same value used for its archive target.
6. **Uploaded and processed**: reachable only in the Owner-consented production-validation slice.

## Failure States

- **App name missing**: terminate before archive; identify the app target without printing credentials.
- **Widget name missing**: terminate before archive; identify the widget target without printing credentials.
- **Names not target-distinct**: terminate before archive; do not map one profile to both targets.
- **Transport invalid**: terminate before archive if an opaque value cannot be represented safely.
- **Archive/export failure**: preserve the existing lane's terminal behavior; do not advance upload, distribution, or release tag.

## Unsigned Compatibility Path

When signing is explicitly disabled, the generated Release project can move directly from configuration generation to unsigned build completion without fetched names, installed profiles, ASC access, or credentials. This path proves compatibility only; it cannot claim signed archive or upload success.

## External Authorization State

- **Consent absent**: no real workflow dispatch is allowed; T005 remains blocked.
- **Consent recorded**: after reviewed merge to `main`, one manual workflow run may proceed.
- **Processed proof recorded**: the run URL and TestFlight build identifier show Apple processing completion without including secret or signing artifacts.

## Recovery and Trusted Review States

1. **Planning approved**: the exact repaired planning revision has independent AI Reviewer PASS and Team Lead approval.
2. **Replacement candidate frozen**: the preserved delivery workspace starts from `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`; the uncommitted tree is split by AppUI/RepoInfra scope for review, while PR #441 remains unchanged.
3. **Replacement published**: only the reviewed tree is committed as clean layer-scoped commits and published on a new branch; PR #441 is then eligible for PR Manager closure with the replacement link.
4. **Bootstrap dependency satisfied**: MY-1675 / PR #442 has merged through its one-time exact-head human bootstrap and the trusted base contains that fix.
5. **Fresh review event accepted**: the replacement receives a fresh eligible `pull_request_target` event after state 4 and records a real schema-valid, passing `codex-review-target` result for its current head.
6. **Shipping eligible**: required checks, including state 5, are valid for the replacement head; no #442 bypass has been reused.

## Forbidden Transitions

- Missing profile output → archive using an action-return fallback.
- App profile value → widget archive or widget export mapping.
- Static/unsigned verification → implied Owner consent.
- Draft or unlabeled implementation PR → production validation.
- Workflow success before Apple processing completion → US2/AC5 satisfied.
- Approved base → direct generated-project edit that omits the `project.yml` baseline exclusion.
- AppUI configuration edit → change to `VitalStride/CONTEXT.md`, an app/package source or test, or a RepoInfra path in the same layer-scoped commit.
- PR #441 → rewritten history, force-push, or closure before the replacement link is published.
- PR #442 bootstrap → authorization for MY-1660 to bypass `codex-review-target`.
- Pre-fix, stale, synthetic, or ineligible review event → replacement shipping evidence.
