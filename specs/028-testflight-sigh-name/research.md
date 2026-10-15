# Research: TestFlight per-call SIGH_NAME capture

## Evidence

- Product base: `663054cb4e7f58459fd0caf6a0710f6e74f18bd0`.
- Failed release: GitHub Actions run `38690610783`, which stops before archive because the app target-derived environment key is absent.
- `fastlane/Fastfile` has exactly two production reads of the fabricated convention and no other repository script reads it.
- Fastlane 2.241.0 `GetProvisioningProfileAction` requires Sigh, calls `Sigh::Manager.start`, reads `ENV["SIGH_NAME"]`, publishes it as `Actions.lane_context[SharedValues::SIGH_NAME]`, reads `SIGH_UUID`, and returns the UUID.
- Lane context stores one scalar name. A later provisioning call overwrites the prior value.
- The existing app/widget specifier variables, shell escaping, export mapping, and missing/blank/equal guards are already correct.
- VoxPocket PR #100 (`d2adaa66eab300952c0782d7250c3780b86252ff`) repaired the same defect with a real-action fixture that replaces `Sigh::Manager.start`, not the action.
- The current RepoInfra gate does not invoke Ruby tests.

## Decision 1: Capture at each action boundary

**Decision**: Capture the app `SIGH_NAME` immediately after its fetch and before the widget fetch; capture the widget value immediately after its fetch.

**Rationale**: The supported output is shared scalar state. Delayed reads cannot reconstruct which call produced the value.

**Rejected alternatives**:

- Target-derived lowercase environment keys: a `match` convention, not published by Sigh.
- Action return: Fastlane documents and implements it as UUID.
- Second lookup or fixed name: adds a divergent source and weakens fail-closed behavior.
- Copy app to widget: violates target distinction.

## Decision 2: Preserve and test fail-closed behavior

**Decision**: Keep missing/blank/equal validation before `build_app`, and prove the actual lane never calls build or upload for these cases.

**Rationale**: A signing value cannot be safely guessed. Early termination protects archive, upload, distribution, and marker state.

## Decision 3: Use a real-action Ruby fixture

**Decision**: Add `scripts/tests/test_testflight_packaging.rb`, load real Fastlane/Sigh and the repository Fastfile, and replace only `Sigh::Manager.start` plus unrelated external credential/build/upload work.

**Rationale**: Static source matching alone cannot prove Fastlane's action publishes and overwrites lane context as assumed. Stubbing the action would merely restate the implementation.

**Rejected alternatives**:

- Python-only source assertions: cannot exercise action return and shared-value behavior.
- Stubbing `get_provisioning_profile`: violates the issue's explicit real-action requirement.
- Running the live lane: needs credentials, mutates Developer Portal state, signs, uploads, and changes release state.

## Decision 4: Keep automatic-release coverage unchanged

**Decision**: Do not edit `scripts/tests/test_testflight_freshness.py` or `.github/workflows/testflight.yml`. Wire the Ruby regression through `scripts/test-repoinfra.sh`.

**Rationale**: `027` owns classifier/orchestration behavior. A separate packaging test isolates the signing-output contract and avoids weakening or coupling the classifier suite.

## Decision 5: No dependency or architecture change

**Decision**: Reuse the Homebrew Fastlane/Ruby environment already present on the release platform. Add no Gemfile, version pin, workflow installation step, ADR, or context change.

**Rationale**: This is a narrow correctness repair inside the existing dependency-free RepoInfra layer. If the required real runtime is unavailable, the test gate must fail rather than skip.

## No open clarification

MY-1815, the failing run, installed Fastlane source, VoxPocket precedent, repository layer rules, and the existing lane settle scope, ordering, compatibility, testing, and post-merge ownership. No product or authority decision remains.
