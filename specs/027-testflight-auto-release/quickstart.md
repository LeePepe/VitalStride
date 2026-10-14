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
- NUL-safe narrow path positives and exclusion-first endpoint precedence match the contract exactly; package tests/contexts and documentation-only changes remain negative; relevant deletion, mixed diffs, and relevant↔excluded rename/copy qualify while excluded↔excluded does not.
- Manual force bypasses only path eligibility.
- Immutable `testflight/attempted/<SHA>` is remotely confirmed before the lane and remains effective across later claims; after all earlier critical phases, the success marker is remotely read back before matching resolution-ref confirmation.
- Immediately before success-marker mutation, immutable `testflight/success-pending/<SHA>` is remotely confirmed. Mutation captures the prior OID, uses it as a lease/CAS expectation, and freshly reads the remote ref; exact candidate readback is followed by remotely confirmed matching `testflight/success-resolved/<SHA>` before success.
- Every authoritative preflight validates pending/resolved ref names and encoded-SHA targets, rejects malformed/mismatched/orphan or confirmed-unpaired state before upload, and treats an exact valid pair as gate reconciliation only. Prior/conflict/unknown or resolution-confirmation outcomes produce safe failure or `success-marker-indeterminate` evidence; ambiguous resolution confirmation fails the current run without a pair assertion, then the next preflight distinguishes exact-pair gate clearing from confirmed-absence Owner recovery. None of these paths invents unchanged state, automatically resolves exceptional evidence, overwrites, deletes, rolls back, or retroactively changes a failed run to success.
- Automatic and manual candidates use the same exact merged-PR/`release:minor` policy.
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
- immutable `testflight/attempted/<candidate>`, success-pending/resolved pair, and remote `testflight/last-released` state;
- confirmation that one upload was attempted for the candidate.

Do not attach secrets, `.p8`, profiles, certificates, keychain output, or unredacted sensitive logs.

A failed run is incident evidence only and does not complete T005 or MY-1766 outcome acceptance, even if later preflight observes an exact valid pair. Do not retry the claimed SHA. Reconcile the recovery gate or complete Owner recovery as required, then wait for a distinct eligible main SHA and require a successful terminal run with confirmed evidence.
