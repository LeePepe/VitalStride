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

## XcodeGen baseline reconciliation and idempotency

The exact reviewed planning revision is the implementation checkout base. Its product/source tree is `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`; do not substitute the divergent `84a153962b50f10cd2f49717c4443fb6e953d4ce` tree or treat `5b81d9c9d5f4acb5b8b0d2a31b1e6158b91f7cf1` as reviewed.

```bash
xcodegen --version
xcodegen generate
git diff --check
git hash-object VitalStride.xcodeproj/project.pbxproj
xcodegen generate
git hash-object VitalStride.xcodeproj/project.pbxproj
```

Expected T001 baseline evidence: the generated output matches the semantic membership/resource/removal manifest in `contracts/testflight-profile-handoff.md`; no source, test, context, or package content changes. Baseline 100 additions/4 deletions with the existing WatchTests/Widgets order or 101/5 with their unchanged references reordered are the only permitted diagnostic variants. The stale app-target `WorkoutSetManager.swift` reference is absent and the package implementation remains present.

Expected assembled T001 evidence: the semantic baseline plus exactly two target-specific Release-setting substitutions (2 additions/2 deletions), yielding diagnostic 102/6 or 103/7. The two hashes from consecutive generations with the recorded same XcodeGen executable must be equal. Cross-version blob/order identity is not required.

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

This build also proves the synchronized project no longer requests deleted `VitalStride/Sources/WorkoutSetManager.swift` and continues to compile against the package-owned implementation.

## Frozen candidate evidence before publication

- Rerun every credential-free command above and `git diff --check` against the complete local candidate.
- Record the uncommitted candidate manifest: relative path, tracked/untracked status, and content hash/blob identity for every candidate file, plus the generated semantic-manifest comparison and verification results.
- Freeze that exact tree. Do not commit, push, or create/update a PR.
- Obtain exact AI Reviewer content `PASS` and explicit publication permission for the frozen manifest. Any content change invalidates the permission and requires a new freeze/review.

## Candidate PR evidence after publication permission

- Commit and push only the unchanged reviewed tree; prove the committed tree matches the reviewed manifest.
- PR is non-Draft.
- PR has the `owner-review` label.
- PR description lists the new-runner manual validation procedure and states that explicit Owner consent is required before dispatch.
- Local commit SHA, remote branch OID, and PR `headRefOid` are identical.
- The published mapping is handed to PR Manager, who owns required-check evidence and merge readiness.
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
