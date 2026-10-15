# Research: TestFlight per-call SIGH_NAME capture

## Evidence

- Implementation base: `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`, the normal merge of completed T001 PR #449.
- Failed release: GitHub Actions run `38690610783`, which stops before archive because the app target-derived environment key is absent.
- `fastlane/Fastfile` has exactly two production reads of the fabricated convention and no other repository script reads it.
- Fastlane 2.238.0 and 2.241.0 `GetProvisioningProfileAction` require Sigh, call `Sigh::Manager.start`, read `ENV["SIGH_NAME"]`, conditionally publish it as `Actions.lane_context[SharedValues::SIGH_NAME]` only when a name exists, read `SIGH_UUID`, and return the UUID.
- `Sigh::Manager.start` and the action do not clear an older `ENV["SIGH_NAME"]` or lane-context name when a current call supplies no name. Both scalar locations can therefore survive a missing current output; a later successful call overwrites the lane-context name.
- The merged Fastfile's app/widget specifier variables, shell escaping, export mapping, two-source pre-call neutralization, immediate per-call capture, and missing/blank/equal guards are correct and read-only for resumed work.
- VoxPocket PR #100 (`d2adaa66eab300952c0782d7250c3780b86252ff`) repaired the same defect with a real-action fixture that replaces `Sigh::Manager.start`, not the action.
- The merged Ruby fixture preserves the intended real-action coverage but hard-activates/asserts Fastlane 2.238.0 and assumes independently PATH-selected `fastlane`, `gem`, and Ruby expose one installation.
- The current RepoInfra gate does not invoke Ruby tests. MY-1820's preserved candidate adds one uncommitted invocation and no other change.
- Required CI runs the gate on `macos-26` without a Fastlane install step and exposes Fastlane 2.238.0. On the observed local executor, unchanged `PATH` resolves a functioning Fastlane 2.241.0 wrapper whose actual RubyGems context is not exposed by independently PATH-selected system `ruby`/`gem`. Both real versions retain the same Sigh action contract. This disproves the exact-version/independent-command premise without authorizing a packaging-layout probe.

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

## Decision 5: Resolve the actual unchanged-PATH Fastlane toolchain

**Decision**: For both the focused test and single mandatory gate invocation, resolve `fastlane` from unchanged `PATH` and use the RubyGems toolchain actually selected/provided by that command. Derive one actual Fastlane version; require the CLI, corresponding gem, loaded library, and loaded Fastlane/Sigh action sources to agree on it; and require it to be at least 2.238.0 before behavioral cases run. Add no Gemfile, dependency installation/version-change step, PATH mutation/workaround, workflow edit, ADR, context change, formula/architecture assumption, alternate runtime/fallback, skip, or hook bypass.

**Rationale**: The actual resolved command is the executor contract; independently PATH-selected Ruby/gem commands need not expose a wrapper's RubyGems context. Version 2.238.0 is the oldest required-runner version verified to implement the needed real-action contract, so it is a compatibility floor rather than an exact selection. Missing Fastlane, an unparseable or below-minimum version, an absent corresponding gem/library, version/source disagreement, or load failure stops the gate rather than skipping, installing, rewriting PATH, or hiding the defect behind another runtime.

**Supersedes**: The formula-only resolver in planning revision `cc2b671adb2659e21a6b05f37e8f9b4db45b78e6` and the exact-2.238.0/independent-command resolver in reviewed revision `7c5fc64430c2b8dbf6c4216cf7e3203790c45821`. Authority: accepted decision `01a13f69-fbe2-76ad-aac4-8ff4d0b2c515` and Team Lead handoff `01a13f78-acd2-744f-bbc8-6ff51c847d3a`. The real-action, stale-state, per-call, fail-closed, and T004 decisions remain unchanged.

## Decision 6: Reconcile work at the merged T001 base

**Decision**: Treat `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8` as the immutable implementation base. T001's merged Fastfile behavior is complete and read-only. Record the necessary current-version resolver adaptation in T002, which owns only `scripts/tests/test_testflight_packaging.rb` and `scripts/test-repoinfra.sh`; T003 verifies and publishes exactly those two paths. The preserved one-line gate candidate remains evidence, not an approved or published revision.

**Rationale**: Reopening the merged production repair or the completed T001 child is unnecessary. The runtime correction stays in the same repository, layer, goal, approach, acceptance surface, and original Fullstack ownership, while the current MY-1820 contract accurately includes the test file it must change.

## Decision 7: Automatic post-merge proof is authoritative

**Decision**: Under Owner-delegated decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9`, T004 observes the qualifying automatic TestFlight `workflow_run` triggered by successful CI on the exact merged `main` SHA. Team Lead records run/head identity, terminal outcome, marker/result state, and uploaded build number. T004 dispatches no release; `force=true` and duplicate upload are forbidden. A manual `force=false` run is supplemental only after the automatic run is terminal and marker-covers that exact SHA, and it cannot replace missing or failed automatic proof.

**Rationale**: The automatic workflow and a default manual run race on the same marker. If automatic wins, manual `force=false` skips; forcing it creates an unauthorized duplicate. Binding acceptance to the qualifying automatic run is deterministic and matches the Owner's auto-publish/no-per-upload-confirmation policy.

**Supersedes**: The earlier planning statement that an unconditional post-merge manual upload would satisfy T004. It does not change the workflow, release policy, or implementation scope.

## No open clarification

MY-1815, implementation base `49b6f1fd0f55493ac55ab4ba8aa18cb80e002fb8`, the merged fixture and lane, verified Fastlane 2.238.0/2.241.0 action sources, VoxPocket precedent, repository layer rules, resolve-actual-fastlane decision `01a13f69-fbe2-76ad-aac4-8ff4d0b2c515`, and Owner-delegated T004 decision `01a13e4b-5ab6-7b69-b6bc-0a9196f541b9` settle scope, ordering, compatibility, testing, runtime, and post-merge evidence. No product or authority decision remains.
