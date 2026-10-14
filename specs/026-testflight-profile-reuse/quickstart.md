# Quickstart: Verify TestFlight profile reuse

Run implementation verification from the repository root.

## Historical red proof (T002, expected historical failure)

After the candidate regression has been authored but before the T002 Fastfile/workflow-comment edits, run it against an isolated overlay of the immutable replacement source base. This leaves T001 and every tracked file unchanged:

```bash
(
  set -o pipefail
  red_fixture="$(mktemp -d "${TMPDIR:-/tmp}/my1660-red.XXXXXX")" || exit 1
  test -d "$red_fixture" || exit 1
  case "$red_fixture" in
    */my1660-red.*) ;;
    *) exit 1 ;;
  esac
  red_log="$red_fixture/historical-red.log"
  cleanup_red_fixture() {
    case "${red_fixture:-}" in
      */my1660-red.*) rm -rf -- "$red_fixture" ;;
    esac
  }
  trap cleanup_red_fixture EXIT HUP INT TERM
  git archive e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b -- \
    .github/workflows/testflight.yml fastlane/Fastfile project.yml \
    | tar -x -C "$red_fixture" || exit 1
  mkdir -p "$red_fixture/scripts/tests" || exit 1
  cp scripts/tests/test_testflight_freshness.py \
    "$red_fixture/scripts/tests/test_testflight_freshness.py" || exit 1
  if (
    cd "$red_fixture" || exit 1
    python3 -B -m unittest scripts.tests.test_testflight_freshness
  ) >"$red_log" 2>&1; then
    printf '%s\n' 'historical fixed-name/fallback fixture unexpectedly passed' >&2
    exit 1
  else
    red_status=$?
  fi
  awk '{ print }' "$red_log"
  test "$red_status" -eq 1 || exit 1
  test "$(rg -c '^FAIL: ' "$red_log")" -eq 2 || exit 1
  rg -F 'HISTORICAL_FIXED_PROFILE_NAMES_REJECTED' "$red_log" >/dev/null || exit 1
  rg -F 'HISTORICAL_ACTION_RETURN_FALLBACK_REJECTED' "$red_log" >/dev/null || exit 1
  test "$(rg -F -x -c 'FAILED (failures=2)' "$red_log")" -eq 1 || exit 1
)
```

Expected: the historical full-module run exits with unittest status 1, reports exactly two `FAIL:` records, includes the two stable markers reserved exclusively for the intended fixed-name and action-return-fallback assertions, and ends with exactly `FAILED (failures=2)`. Any additional failure, error, skip, expected failure, unexpected success, archive/extraction/copy/import/setup failure, or fixture failure changes that exact shape and is rejected. The only deleted path is the non-empty temporary directory returned by successful `mktemp`; run the separate full-module final-green command only in the repaired working tree.

## Final focused credential-free regression

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
```

Expected: existing workflow-freshness cases and the new app/widget profile-handoff cases pass without credentials, profiles, signing, network access, or upload. Red-capable cases reject absent/nil and whitespace-only outputs while accepting distinct nonblank names with leading, trailing, or embedded whitespace and preserving each original value verbatim through archive and export.

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
- Publish from immutable replacement source/ancestry base `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` on a new replacement branch in the preserved delivery workspace. Do not force-push, rewrite PR #441, or substitute the later trusted event base for this ancestry.
- PR is non-Draft.
- PR has the `owner-review` label.
- PR description lists the new-runner manual validation procedure and states that explicit Owner consent is required before dispatch.
- The frozen reviewed tree OID equals the final published commit's tree OID; separately, the local final commit SHA equals the remote branch OID and replacement PR `headRefOid`. After the replacement is published, PR Manager closes PR #441 with the replacement link.
- No comment claims a real upload occurred during implementation verification.

## Trusted-review shipping gate (T004)

Replacement publication and the #442 merge may progress independently, but PR Manager must not ship until both paths converge at T004 and all of the following evidence exists:

1. MY-1675 / PR #442 merged through its one-time human bootstrap bound to the exact authorized #442 head.
2. Default branch `main` contains the merged #442 fix.
3. The replacement's current head received a fresh eligible `pull_request_target` event (`opened`, `synchronize`, or `reopened`) whose trusted event base, `github.event.pull_request.base.sha`, is that fixed `main` revision.
4. That event produced a real, schema-valid, passing `codex-review-target` result for the replacement head while the replacement retained its immutable `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b` source ancestry.

The immutable replacement source base and the trusted event base are separate identities; advancing `main` to the #442-fixed event base never authorizes a rebase or history rewrite. The #442 bootstrap is not reusable by MY-1660. A stale, pre-fix, synthetic, manual, or schema-invalid result does not satisfy this gate. Record the source-base SHA, #442 merge/bootstrap identity, trusted event-base revision, replacement event/base/head, and check-run URL/app/head/schema/conclusion; do not edit the workflow or review scripts as part of this feature.

## Forbidden during implementation and review

Do not run `fastlane ios beta`, dispatch `.github/workflows/testflight.yml`, contact ASC for a release, mutate Developer Portal signing state, or upload/distribute a build. Those actions require fresh explicit Owner consent.

## Owner-controlled production validation (T005)

This section is not an implementation command. It becomes executable only after T004 passes, the reviewed non-Draft replacement PR is merged to `main`, and the Owner's explicit upload consent is recorded.

1. Confirm the consent record identifies this validation and is still current.
2. Manually run the repository's `testflight` workflow on `main`; keep the existing `force` semantics unchanged.
3. Confirm the workflow archives, uploads, and reaches terminal success.
4. Confirm the uploaded build reaches Apple processing completion.
5. Record only the consent reference, workflow run URL, and processed build identifier. Do not attach or quote secrets, certificates, keychain data, `.p8`, or provisioning-profile contents.
