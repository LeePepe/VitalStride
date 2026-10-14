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
xcodegen --version
xcodegen generate
git diff --check
```

Expected:

- `project.yml` contains the baseline-reconciliation exclusion for `VitalStride/CONTEXT.md` in the `VitalStride` target and exactly the two intended Release profile-specifier substitutions.
- `VitalStride.xcodeproj/project.pbxproj` contains no file or resource reference for `VitalStride/CONTEXT.md`; it is generated synchronization evidence and is never edited directly.
- Record the XcodeGen version and executable used. Regenerate a second time with that same executable and require the generated project blob to remain unchanged.
- The diff has no whitespace errors. The historical generated `99/7` numstat is diagnostic, not an acceptance requirement.

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

- Before any commit, push, or PR publication, freeze the local candidate tree and obtain an exact-tree AI Reviewer content PASS with explicit publication permission. Any content change invalidates that permission.
- After publication permission, preserve one AppUI commit for the `project.yml` baseline/profile edits plus generated synchronization and one separate RepoInfra commit for the regression/lane repair.
- Publish from `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` on a new replacement branch in the preserved delivery workspace. Do not force-push or rewrite PR #441.
- PR is non-Draft.
- PR has the `owner-review` label.
- PR description lists the new-runner manual validation procedure and states that explicit Owner consent is required before dispatch.
- Local, remote, and replacement PR heads identify the unchanged reviewed tree. After the replacement is published, PR Manager closes PR #441 with the replacement link.
- No comment claims a real upload occurred during implementation verification.

## Trusted-review shipping gate (T004)

The replacement may be prepared and published while this external dependency is blocked, but PR Manager must not ship it until all of the following evidence exists:

1. MY-1675 / PR #442 merged through its one-time human bootstrap bound to the exact authorized #442 head.
2. The trusted base used for the replacement contains the #442 fix.
3. The replacement's current head received a fresh eligible `pull_request_target` event (`opened`, `synchronize`, or `reopened`) after that merge.
4. That event produced a real, schema-valid, passing `codex-review-target` result for the replacement head.

The #442 bootstrap is not reusable by MY-1660. A stale, pre-fix, synthetic, manual, or schema-invalid result does not satisfy this gate. Record the #442 merge/bootstrap identity, trusted-base revision, replacement event/base/head, and check-run URL/app/head/schema/conclusion; do not edit the workflow or review scripts as part of this feature.

## Forbidden during implementation and review

Do not run `fastlane ios beta`, dispatch `.github/workflows/testflight.yml`, contact ASC for a release, mutate Developer Portal signing state, or upload/distribute a build. Those actions require fresh explicit Owner consent.

## Owner-controlled production validation (T005)

This section is not an implementation command. It becomes executable only after T004 passes, the reviewed non-Draft replacement PR is merged to `main`, and the Owner's explicit upload consent is recorded.

1. Confirm the consent record identifies this validation and is still current.
2. Manually run the repository's `testflight` workflow on `main`; keep the existing `force` semantics unchanged.
3. Confirm the workflow archives, uploads, and reaches terminal success.
4. Confirm the uploaded build reaches Apple processing completion.
5. Record only the consent reference, workflow run URL, and processed build identifier. Do not attach or quote secrets, certificates, keychain data, `.p8`, or provisioning-profile contents.
