# Quickstart: TestFlight auto-release implementation verification

## Preconditions

- Work from the exact Team Lead-approved implementation base containing the independently reviewed `specs/027-testflight-auto-release/**` revision.
- Confirm the implementation diff is limited to:
  - `.github/workflows/testflight.yml`
  - `fastlane/Fastfile`
  - `scripts/tests/test_testflight_freshness.py`
- Do not dispatch TestFlight, read secret values, mutate tags, or contact App Store Connect during local verification.
- `.github/workflows/testflight.yml` publication requires explicit Owner approval; content review does not grant it.

## Red-first contract cycle

1. Update credential-free tests for the selected task contract.
2. Run the focused suite and capture the expected contract failure before production edits.
3. Change only the task-owned RepoInfra paths.
4. Rerun until the focused suite reports zero failures/errors.

## Required local evidence

From repository root:

```bash
python3 -B -m unittest scripts.tests.test_testflight_freshness
ruby -c fastlane/Fastfile
bash scripts/test-repoinfra.sh
git diff --check
git status --short
```

Read the full RepoInfra output. Exit code alone is insufficient because the planning environment exposed a nested Python test failure/error while the wrapper returned zero.

No `xcodebuild` or package build/test is part of this RepoInfra-only verification. If the diff enters AppUI or `Packages/**`, stop as out of scope rather than expanding the command set.

## Static inspection

- Automatic candidate is the exact successful `CI` push/main head SHA.
- Full-history/tag checkout precedes marker/diff decisions.
- Path allowlist and exclusions match the contract exactly.
- Manual force bypasses only path eligibility.
- Attempt marker is remotely confirmed before the lane; success marker is remotely confirmed last.
- Marketing version has one resolved source reused across archive and lookup.
- Build-number query remains app-wide and its chosen value reaches workflow evidence.
- No critical phase can continue on failure or retry.
- Existing dynamic profile/signing/telemetry inputs remain unchanged.
- Only the three implementation paths changed.

## Review and publication evidence

- Freeze the exact local candidate and capture its SHA/tree/diff plus fresh command results.
- Obtain independent AI Reviewer verdict for that exact candidate according to the Dev Team pre-push flow.
- Publish only the reviewed SHA through the normal non-Draft PR path.
- Record explicit Owner approval for the `.github/**` change before merge.
- PR Manager owns required-check and merge/shipping state; Team Lead owns recovery/escalation.

## Post-merge operational evidence

For the first eligible successful main CI candidate, record on MY-1766:

- exact candidate/CI SHA;
- TestFlight workflow run URL and terminal conclusion;
- runtime marketing version and unique build number;
- remote `testflight/last-attempted` and `testflight/last-released` SHAs;
- confirmation that one upload was attempted for the candidate.

Do not attach secrets, `.p8`, profiles, certificates, keychain output, or unredacted sensitive logs.
