# Research: TestFlight in-run profile reuse

## Evidence

- Planning base: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- Reviewed planning revision `b26401eb2aabd0c41e412ffb904b270e67109650` is a direct child of that product base and changes only this feature's eight planning artifacts; it does not repair the stale project.
- `fastlane/Fastfile` regenerates the Xcode project, fetches separate app and widget App Store profiles with `force: true` and installation enabled, then invokes `build_app`.
- Archive-time `xcargs` currently contains build number, team, and telemetry values but no target-specific provisioning-profile inputs.
- Export mapping reads the canonical Fastlane profile-name environment outputs but falls back to the provisioning action return values.
- `project.yml` keeps base signing Automatic, while the app and widget Release configurations are Manual and each contain a fixed profile display name.
- `.github/workflows/testflight.yml` is manual-only, checks out `main`, retains `force=false` by default, skips when no new commit exists unless forced, and never cancels an in-progress upload.
- `scripts/tests/test_testflight_freshness.py` already has four passing static tests for those workflow invariants. `scripts/test-repoinfra.sh` auto-discovers that module and the PR `Lint & policy` job invokes the complete gate.
- A real lane run queries ASC, can regenerate Developer Portal profiles, archives, uploads, distributes to internal groups, and advances the release tag. It is not a safe implementation test.
- Exact-ref audit found no usable synchronized descendant of `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`. Historical generated commit `84a153962b50f10cd2f49717c4443fb6e953d4ce` has the same `project.yml` blob and the required membership result, but diverges from the product base by 93 files and therefore cannot be substituted. Local implementation commit `5b81d9c9d5f4acb5b8b0d2a31b1e6158b91f7cf1` is unreviewed and is evidence only.
- Exact object evidence shows the same `project.yml` blob produces the semantic baseline as 100 additions/4 deletions at `84a1539` or 101/5 in the observed candidate decomposition; the only difference is the relative order of unchanged `VitalStrideWatchTests` and `VitalStrideWidgets` target references. The generated memberships select accepted files already declared by `project.yml`; the only removed membership is the stale app-target reference to `VitalStride/Sources/WorkoutSetManager.swift`, whose implementation already moved to `Packages/VitalModels/Sources/VitalModels/Repo/WorkoutSetManager.swift` under accepted commit `cc3078c64dd2556fa4cdaa38266b80aba1b71029`. T001's two Release-setting substitutions are exactly 2/2, so the assembled diagnostic numstat is 102/6 or 103/7.
- CI installs XcodeGen with unversioned `brew install xcodegen`; the repository contains no generator-version pin. Semantic manifest equality is therefore authoritative, while two-run blob equality proves idempotency only with the recorded same installed executable.

## Decision 1: One target-specific two-value interface

**Decision**: Define `VITALSTRIDE_APP_PROFILE_SPECIFIER` and `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` as the only archive inputs for the app and widget Release `PROVISIONING_PROFILE_SPECIFIER` settings.

**Rationale**: Global build arguments can carry two distinct custom values while each target consumes only its own key. The project source remains the long-lived XcodeGen truth, no generated-project mutation action is needed, and app/widget identity cannot collapse into one global `PROVISIONING_PROFILE_SPECIFIER` override.

**Alternatives considered**:

- Override `PROVISIONING_PROFILE_SPECIFIER` once in global `xcargs`. Rejected because both targets would receive the same profile.
- Mutate the generated Xcode project target-by-target during the lane. Rejected because it adds a second project-editing mechanism when the two-key XcodeGen seam expresses the behavior directly.
- Keep the two fixed names and rename profiles in Developer Portal. Rejected by DEC-026-001 because it restores the manual operational dependency that caused the incident.

## Decision 2: Canonical outputs fail closed and drive archive plus export

**Decision**: After both forced fetches, resolve the existing canonical profile-name outputs, require both non-empty target-distinct values, shell-escape them for archive arguments, and reuse the same resolved variables in export mapping.

**Rationale**: Archive and export cannot drift when both cross the same interface. Failing before `build_app` is safer and more diagnosable than accepting an action return value whose meaning differs from the canonical display-name output. Opaque escaping prevents whitespace or metacharacters from changing argument structure.

**Alternatives considered**:

- Retain the action-return fallback. Rejected because it provides a second source and can conceal a missing canonical name until signing or export.
- Look up the installed profile a second time. Rejected because the fetch already publishes the required name and a second lookup increases state and test surface.
- Log resolved credentials/profile contents for diagnosis. Rejected because the name is sufficient for a target-specific error and signing/credential contents are excluded.

## Decision 3: Extend the existing PR static contract

**Decision**: Extend `scripts/tests/test_testflight_freshness.py` to inspect `fastlane/Fastfile` and `project.yml` in addition to the workflow, preserving its existing assertions.

**Rationale**: The module already owns TestFlight release-policy freshness, is auto-discovered by the fast RepoInfra gate, and runs on every pull request. Static contract coverage can prove the two fetches, canonical sources, two project keys, target mapping, shell-safe handoff, fail-closed behavior, and absence of fixed names/fallback without Apple access.

**Alternatives considered**:

- Add a new workflow job. Rejected because the existing required policy job already provides PR-time execution.
- Run `fastlane ios beta` in CI. Rejected because it needs secrets, mutates external state, signs, uploads, and violates DEC-026-003.
- Rely only on an unsigned app build. Rejected because signing-disabled builds cannot prove which profile the signed archive would select.

## Decision 4: Separate credential-free delivery from production validation

**Decision**: Deliver implementation through static, syntax, RepoInfra, XcodeGen, and unsigned Release evidence; freeze that local evidence for exact content review before publication; after explicit publication permission, publish the unchanged candidate for PR Manager-owned required-check/merge evidence. Keep the real TestFlight run as a separate slice blocked by reviewed merge plus explicit Owner consent.

**Rationale**: The scoped Owner-approved VitalStride delivery contract requires freeze → review/permission → publication and avoids treating PR state as prepublication review evidence. The implementation can be fully content-reviewed without external mutation; after permission, the non-Draft `owner-review` PR provides the PR Manager shipping surface, while the final operational outcome still receives a controlled new-runner proof.

## Decision 5: No ADR or domain-context change

**Decision**: Do not add an ADR or edit `CONTEXT.md`.

**Rationale**: This repair follows existing AppUI/RepoInfra ownership, XcodeGen truth-source, manual TestFlight, and PR-required decisions. It introduces no durable product terminology, dependency direction, public interface, or architecture reversal.

## Decision 6: Keep generated reconciliation inside the AppUI truth-source task

**Decision**: T001, the AppUI task that owns `project.yml`, first records the installed generator and captures the contract's semantic baseline as a separately reviewable generated-evidence component, then changes the two Release settings in `project.yml` and regenerates. `VitalStride.xcodeproj/**` remains an unschedulable generated exclusion; a repeated run with the same executable proves idempotency and the unsigned Release build proves compatibility. One frozen candidate may carry both ordered evidence components; no history rewrite is required merely to manufacture separate commits.

**Rationale**: Constitution Principle IV forbids a hand-edited settings-only project, while ADR-0019 forbids treating generated output as schedulable AppUI content and using a divergent historical tree would discard accepted product work. Ordered semantic evidence inside T001 makes both components reviewable while preserving the exact product base and layer ownership.

**Alternatives considered**:

- Use `84a153962b50f10cd2f49717c4443fb6e953d4ce` as the implementation base. Rejected because it is not an ancestor/descendant of the current product base and carries 93 files of unrelated tree difference.
- Accept `5b81d9c9d5f4acb5b8b0d2a31b1e6158b91f7cf1` as-is. Rejected because it combines the prerequisite and feature changes and has no passing exact-revision review.
- Hand-edit only the two profile settings. Rejected because it leaves the deleted app `WorkoutSetManager.swift` reference, fails the unsigned build, and violates the XcodeGen source-of-truth rule.

## Decision 7: Review the frozen tree before publication

**Decision**: T003 has a hard two-stage gate. Stage A freezes the uncommitted local candidate manifest and credential-free results and obtains exact AI Reviewer content `PASS` plus explicit publication permission. Stage B may then commit/push/create-or-update the non-Draft `owner-review` PR only if the tree is unchanged, prove reviewed-tree/local/remote/PR identity, and hand the published mapping to PR Manager. Any content change returns to Stage A.

**Rationale**: This is the Owner-approved VitalStride workspace override for prepublication review. It controls this delivery without changing repository ADR-0021's post-publication role ownership: Fullstack still publishes, AI Reviewer still reviews content, and PR Manager still owns required checks, merge, and cleanup.

## No open clarification

MY-1606 revision 3, the Team Lead handoff, Constitution Principle IV, ADR-0019, the AppUI/RepoInfra contexts, the Owner-approved scoped delivery override, and accepted source history settle target behavior, compatibility, semantic generated membership scope, prepublication order, PR constraints, and the Owner-consent boundary. No product or authority choice remains for implementation; only T004 stays intentionally blocked until the Owner supplies the required external consent.
