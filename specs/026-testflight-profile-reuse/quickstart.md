# Quickstart: Verify TestFlight profile reuse

Run implementation verification from the repository root.

## Focused credential-free regression

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
```

Expected: existing workflow-freshness cases and the new app/widget profile-handoff cases pass without credentials, profiles, signing, network access, or upload.

## Fastfile syntax

```bash
ruby -c fastlane/Fastfile
```

Expected: `Syntax OK`.

## Complete RepoInfra gate

```bash
bash scripts/test-repoinfra.sh
```

Expected: path/frontmatter checks, shell/Python syntax checks, and all auto-discovered RepoInfra tests pass.

## XcodeGen synchronization

```bash
xcodegen generate
git diff --check
```

Expected: the tracked Xcode project reflects only the intended Release build-setting changes and the diff has no whitespace errors. On a committed candidate, regenerating again must leave `VitalStride.xcodeproj/project.pbxproj` unchanged.

## Unsigned Release compatibility

```bash
xcodebuild build \
  -project VitalStride.xcodeproj \
  -scheme VitalStride \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/my-1606-derived-data \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

Expected: the Release build completes without Apple credentials, installed profiles, dynamic profile values, or real signing.

## Candidate PR evidence

- PR is non-Draft.
- PR has the `owner-review` label.
- PR description lists the new-runner manual validation procedure and states that explicit Owner consent is required before dispatch.
- Required PR checks are recorded by PR Manager under the normal delivery contract.
- No comment claims a real upload occurred during implementation verification.

## Forbidden during implementation and review

Do not run `fastlane ios beta`, dispatch `.github/workflows/testflight.yml`, contact ASC for a release, mutate Developer Portal signing state, or upload/distribute a build. Those actions require fresh explicit Owner consent.

## Owner-controlled production validation

This section is not an implementation command. It becomes executable only after the reviewed non-Draft PR is merged to `main` and the Owner's explicit upload consent is recorded.

1. Confirm the consent record identifies this validation and is still current.
2. Manually run the repository's `testflight` workflow on `main`; keep the existing `force` semantics unchanged.
3. Confirm the workflow archives, uploads, and reaches terminal success.
4. Confirm the uploaded build reaches Apple processing completion.
5. Record only the consent reference, workflow run URL, and processed build identifier. Do not attach or quote secrets, certificates, keychain data, `.p8`, or provisioning-profile contents.
