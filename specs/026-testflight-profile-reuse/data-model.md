# State Model: TestFlight profile handoff

No product entity, persisted schema, or user data changes. The relevant model is ephemeral release state.

## Generated Project States

1. **Reviewed checkout**: exact reviewed planning revision whose non-planning product tree is `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`; tracked project is stale.
2. **Semantic baseline captured**: inside T001, generated evidence matches the handoff manifest irrespective of the permitted WatchTests/Widgets target-reference order; no source/config content changed and `VitalStride.xcodeproj/**` acquired no layer ownership.
3. **Signing seam synchronized**: T001 has changed only the two target-specific `project.yml` profile settings and regenerated exactly two corresponding setting substitutions beyond the semantic baseline.
4. **Generation idempotent**: a second run with the recorded same installed XcodeGen executable leaves the assembled project blob unchanged; cross-version blob/order identity is not implied.

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

- **Consent absent**: no real workflow dispatch is allowed; T004 remains blocked.
- **Consent recorded**: after reviewed merge to `main`, one manual workflow run may proceed.
- **Processed proof recorded**: the run URL and TestFlight build identifier show Apple processing completion without including secret or signing artifacts.

## Publication States

1. **Candidate frozen**: the uncommitted local tree, complete candidate manifest, semantic generated-project comparison, and credential-free results are immutable review inputs; no commit, push, or PR creation/update has occurred.
2. **Publication permitted**: exact AI Reviewer content `PASS` and explicit permission identify that frozen tree. Any content change returns to **Candidate frozen** after new evidence is produced.
3. **Candidate published**: Fullstack has committed and pushed only the reviewed tree and created or updated the non-Draft `owner-review` PR; reviewed tree = commit tree and local SHA = remote branch OID = PR `headRefOid`.
4. **PR Manager handoff recorded**: the published mapping and a verified PR Manager run transfer required-check, merge, and cleanup ownership.

## Forbidden Transitions

- Missing profile output → archive using an action-return fallback.
- App profile value → widget archive or widget export mapping.
- Static/unsigned verification → implied Owner consent.
- Draft or unlabeled implementation PR → production validation.
- Workflow success before Apple processing completion → US2/AC5 satisfied.
- Stale reviewed checkout → settings-only hand edit that retains `VitalStride/Sources/WorkoutSetManager.swift`.
- Divergent historical project tree or unreviewed implementation commit → substituted implementation base.
- Semantic baseline reconciliation → any source/test edit, generated membership outside the handoff manifest, or structural change other than the permitted unchanged WatchTests/Widgets target-reference order.
- Frozen candidate without exact content `PASS` and publication permission → commit, push, or PR creation/update.
- Reviewed frozen candidate → changed content while retaining prior publication permission.
- Published candidate → commit tree or local/remote/PR identity different from the reviewed manifest.
