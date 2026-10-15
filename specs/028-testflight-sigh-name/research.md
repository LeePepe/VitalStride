# Research: TestFlight per-call SIGH_NAME capture

## Evidence

- Product base: `663054cb4e7f58459fd0caf6a0710f6e74f18bd0`.
- Failed release: GitHub Actions run `38690610783`, which stops before archive because the app target-derived environment key is absent.
- `fastlane/Fastfile` has exactly two production reads of the fabricated convention and no other repository script reads it.
- Fastlane 2.238.0 and 2.241.0 `GetProvisioningProfileAction` require Sigh, call `Sigh::Manager.start`, read `ENV["SIGH_NAME"]`, conditionally publish it as `Actions.lane_context[SharedValues::SIGH_NAME]` only when a name exists, read `SIGH_UUID`, and return the UUID.
- `Sigh::Manager.start` and the action do not clear an older `ENV["SIGH_NAME"]` or lane-context name when a current call supplies no name. Both scalar locations can therefore survive a missing current output; a later successful call overwrites the lane-context name.
- The existing app/widget specifier variables, shell escaping, export mapping, and missing/blank/equal guards are already correct.
- VoxPocket PR #100 (`d2adaa66eab300952c0782d7250c3780b86252ff`) repaired the same defect with a real-action fixture that replaces `Sigh::Manager.start`, not the action.
- The current RepoInfra gate does not invoke Ruby tests.

## Decision 1: Capture at each action boundary

**Decision**: Immediately before each real fetch, neutralize both `ENV["SIGH_NAME"]` and `Actions.lane_context[SharedValues::SIGH_NAME]`. Capture the app lane-context name immediately after its fetch and before the widget fetch; independently repeat neutralization and immediate capture for the widget.

**Rationale**: The supported handoff spans two independently stale-capable scalar locations, and the real action publishes conditionally. Clearing only fixture state or only one location cannot prove the captured value originated from the current invocation. Pre-call two-source neutralization plus immediate post-call capture establishes provenance.

**Rejected alternatives**:

- Clearing only test-fixture state: does not protect production from state left by a prior target or lane.
- Clearing only environment or only lane context: the uncleared location can still satisfy a missing-output read.
- Target-derived lowercase environment keys: a `match` convention, not published by Sigh.
- Action return: Fastlane documents and implements it as UUID.
- Second lookup or fixed name: adds a divergent source and weakens fail-closed behavior.
- Copy app to widget: violates target distinction.

## Decision 2: Preserve and test fail-closed behavior

**Decision**: Keep missing/blank/equal validation before `build_app`. Add separate real-action negatives that seed stale values in both locations: missing app output must produce an app-specific failure before widget/build work; valid app capture followed by missing widget output must produce a widget-specific failure while preserving the local app capture and stopping before build work.

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

**Decision**: Reuse the Homebrew Fastlane/Ruby environment already present on both supported executors. Resolve `brew --prefix fastlane` and `brew --prefix ruby` dynamically; use the formula Ruby with the formula's `libexec` on `GEM_PATH` for both the focused test and the single mandatory gate invocation. Add no Gemfile, version pin, workflow installation step, ADR, or context change, and never fall back to ambient `/usr/bin/ruby`.

**Rationale**: Required CI currently supplies Fastlane 2.238.0 and the release host supplies 2.241.0 with the same relevant action contract. Dynamic formula-prefix resolution is portable across those executor versions and ARM/Intel Homebrew layouts without expanding into workflow edits. If the required real runtime is unavailable, the test gate must fail rather than skip or install.

## Decision 6: Automatic post-merge proof is authoritative

**Decision**: Under Owner-delegated decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9`, T004 observes the qualifying automatic TestFlight `workflow_run` triggered by successful CI on the exact merged `main` SHA. Team Lead records run/head identity, terminal outcome, marker/result state, and uploaded build number. T004 dispatches no release; `force=true` and duplicate upload are forbidden. A manual `force=false` run is supplemental only after the automatic run is terminal and marker-covers that exact SHA, and it cannot replace missing or failed automatic proof.

**Rationale**: The automatic workflow and a default manual run race on the same marker. If automatic wins, manual `force=false` skips; forcing it creates an unauthorized duplicate. Binding acceptance to the qualifying automatic run is deterministic and matches the Owner's auto-publish/no-per-upload-confirmation policy.

**Supersedes**: The earlier planning statement that an unconditional post-merge manual upload would satisfy T004. It does not change the workflow, release policy, or implementation scope.

## No open clarification

MY-1815, the failing run, installed Fastlane source, VoxPocket precedent, repository layer rules, the existing lane, and Owner-delegated decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9` settle scope, ordering, compatibility, testing, runtime, and post-merge evidence. No product or authority decision remains.
