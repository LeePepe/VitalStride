# State Model: TestFlight profile handoff

No product entity, persisted schema, or user data changes. The relevant model is ephemeral release state.

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

## Forbidden Transitions

- Missing profile output → archive using an action-return fallback.
- App profile value → widget archive or widget export mapping.
- Static/unsigned verification → implied Owner consent.
- Draft or unlabeled implementation PR → production validation.
- Workflow success before Apple processing completion → US2/AC5 satisfied.
