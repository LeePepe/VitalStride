# Research: TestFlight in-run profile reuse

## Evidence

- Planning base: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- `fastlane/Fastfile` regenerates the Xcode project, fetches separate app and widget App Store profiles with `force: true` and installation enabled, then invokes `build_app`.
- Archive-time `xcargs` currently contains build number, team, and telemetry values but no target-specific provisioning-profile inputs.
- Export mapping reads the canonical Fastlane profile-name environment outputs but falls back to the provisioning action return values.
- `project.yml` keeps base signing Automatic, while the app and widget Release configurations are Manual and each contain a fixed profile display name.
- At the approved base, the `VitalStride` source entry excludes only `*.entitlements`; XcodeGen therefore treats support-only `VitalStride/CONTEXT.md` as target input. Root `CONTEXT.md` classifies `**/CONTEXT.md` as support exclusions, and the repaired candidate demonstrated that the exclusion plus profile substitutions removes the unintended generated references.
- `.github/workflows/testflight.yml` is manual-only, checks out `main`, retains `force=false` by default, skips when no new commit exists unless forced, and never cancels an in-progress upload.
- `scripts/tests/test_testflight_freshness.py` already has four passing static tests for those workflow invariants. `scripts/test-repoinfra.sh` auto-discovers that module and the PR `Lint & policy` job invokes the complete gate.
- A real lane run queries ASC, can regenerate Developer Portal profiles, archives, uploads, distributes to internal groups, and advances the release tag. It is not a safe implementation test.
- The Owner-authorized recovery preserves PR #441, uses the preserved delivery workspace on a new branch from `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`, and requires clean AppUI/RepoInfra commits without force-push.
- MY-1675 / PR #442 carries the trusted `codex-review-target` control-plane repair. Its one-time human bootstrap is bound to the exact #442 head and cannot be reused by the MY-1660 replacement.
- The trusted workflow checks out and evaluates `github.event.pull_request.base.sha`; for T004 this is the fresh eligible `pull_request_target` event's default-branch `main` base revision, not the replacement branch's immutable source base.

## Decision 1: One target-specific two-value interface

**Decision**: Define `VITALSTRIDE_APP_PROFILE_SPECIFIER` and `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` as the only archive inputs for the app and widget Release `PROVISIONING_PROFILE_SPECIFIER` settings.

**Rationale**: Global build arguments can carry two distinct custom values while each target consumes only its own key. The project source remains the long-lived XcodeGen truth, no generated-project mutation action is needed, and app/widget identity cannot collapse into one global `PROVISIONING_PROFILE_SPECIFIER` override.

**Alternatives considered**:

- Override `PROVISIONING_PROFILE_SPECIFIER` once in global `xcargs`. Rejected because both targets would receive the same profile.
- Mutate the generated Xcode project target-by-target during the lane. Rejected because it adds a second project-editing mechanism when the two-key XcodeGen seam expresses the behavior directly.
- Keep the two fixed names and rename profiles in Developer Portal. Rejected by DEC-026-001 because it restores the manual operational dependency that caused the incident.

## Decision 2: Canonical outputs fail closed and drive archive plus export

**Decision**: After both forced fetches, resolve the existing canonical profile-name outputs. Reject an absent/nil output or one whose validation-only whitespace-stripped view is empty, compare the preserved raw values for target distinction, shell-safely transport each original nonblank value to archive, and reuse the same original variables in export mapping.

**Rationale**: Archive and export cannot drift when both cross the same interface. Failing before `build_app` is safer and more diagnosable than accepting an action return value whose meaning differs from the canonical display-name output. A stripped view distinguishes an unusable whitespace-only output without mutating a valid opaque name containing leading, trailing, or embedded whitespace. Opaque escaping prevents that original whitespace or shell metacharacters from changing argument structure.

**Alternatives considered**:

- Retain the action-return fallback. Rejected because it provides a second source and can conceal a missing canonical name until signing or export.
- Look up the installed profile a second time. Rejected because the fetch already publishes the required name and a second lookup increases state and test surface.
- Log resolved credentials/profile contents for diagnosis. Rejected because the name is sufficient for a target-specific error and signing/credential contents are excluded.

## Decision 3: Extend the existing PR static contract

**Decision**: Extend `scripts/tests/test_testflight_freshness.py` to inspect `fastlane/Fastfile` and `project.yml` in addition to the workflow, preserving its existing assertions. After authoring the candidate regression but before T002 production edits, copy that test over an isolated temporary archive of the exact immutable-base workflow, Fastfile, and project file; require a captured nonzero run that identifies both historical fixed-name and action-return-fallback violations. Run the final green commands separately on the repaired working tree.

**Rationale**: The module already owns TestFlight release-policy freshness, is auto-discovered by the fast RepoInfra gate, and runs on every pull request. Static contract coverage can prove the two fetches, canonical sources, two project keys, target mapping, shell-safe handoff, whitespace-only rejection, verbatim nonblank transport, and absence of fixed names/fallback without Apple access. The immutable-base overlay preserves T001→T002 ordering: it reproduces the full historical source state without reverting T001, changing tracked files, or crossing layer ownership.

**Alternatives considered**:

- Add a new workflow job. Rejected because the existing required policy job already provides PR-time execution.
- Run `fastlane ios beta` in CI. Rejected because it needs secrets, mutates external state, signs, uploads, and violates DEC-026-003.
- Rely only on an unsigned app build. Rejected because signing-disabled builds cannot prove which profile the signed archive would select.

## Decision 4: Separate credential-free delivery from production validation

**Decision**: Deliver implementation through static, syntax, RepoInfra, XcodeGen, unsigned Release, and required PR evidence. Keep the real TestFlight run as a separate slice blocked by reviewed merge plus explicit Owner consent.

**Rationale**: The implementation can be fully reviewed without external mutation, while the issue's final operational outcome still receives a controlled new-runner proof. The non-Draft PR and `owner-review` label make the decision point visible before release.

## Decision 5: Classify the context exclusion as AppUI baseline reconciliation

**Decision**: T001 first adds `CONTEXT.md` to the `VitalStride` source exclusions in `project.yml`, then applies the two profile substitutions. The exclusion and substitutions remain one AppUI task/commit; the generated project is synchronized evidence, and `VitalStride/CONTEXT.md` content remains untouched.

**Rationale**: The file is already a support exclusion by root context, while `project.yml` is the AppUI truth source. Encoding the omission there removes accidental resource membership without changing product behavior or creating a generated-output layer. Keeping the three truth-source edits in T001 preserves the AppUI/RepoInfra task and commit boundary.

**Alternatives considered**:

- Treat the context file as a legitimate app resource. Rejected because it contradicts the repository support-exclusion contract and the Owner decision.
- Hand-edit the generated references. Rejected by Constitution Principle IV; regeneration would restore them.
- Move the exclusion into RepoInfra. Rejected because `project.yml` is AppUI-owned even when release automation consumes its output.

## Decision 6: Preserve forward-only replacement history and require a fresh trusted review event

**Decision**: Freeze and independently review the uncommitted replacement tree, then publish it as one AppUI commit followed by one RepoInfra commit on a new branch whose immutable source/ancestry base is `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`. Keep PR #441 unchanged until the replacement exists. Independently, #442 must merge through its one-time exact-head bootstrap so default branch `main` contains the fix. T004 joins replacement publication with that dependency through a fresh eligible `pull_request_target` event; the event's trusted base is `github.event.pull_request.base.sha` on `main`, and it must produce a real schema-valid, passing `codex-review-target` result for the replacement head.

**Rationale**: A replacement avoids rewriting PR #441's mixed-layer history, while the post-#442 event ensures the replacement uses the repaired trusted control plane. Source ancestry and event trust are separate identities: advancing the event base cannot rebase or rewrite the replacement. Replacement publication and #442 merge can progress independently and converge only at T004. A bootstrap exception is not a transferable review result.

**Alternatives considered**:

- Force-push or rewrite PR #441. Rejected by the Owner recovery decision.
- Reuse #442's human bootstrap for MY-1660. Rejected because it is one-time and exact-head scoped.
- Accept a pre-#442, stale, or synthetic check result. Rejected because it does not prove the fixed trusted workflow evaluated the replacement head.

## Decision 7: No ADR or domain-context change

**Decision**: Do not add an ADR or edit `CONTEXT.md`.

**Rationale**: This repair follows existing AppUI/RepoInfra ownership, XcodeGen truth-source, manual TestFlight, and PR-required decisions. It introduces no durable product terminology, dependency direction, public interface, or architecture reversal. Excluding the unchanged context document implements the existing support-exclusion contract rather than changing it.

## No open clarification

MY-1606 revision 3 and the Team Lead handoff settle target behavior, compatibility, scope, recovery, shipping prerequisites, and the Owner-consent boundary. No product or authority choice remains for implementation. T004 is an external shipping dependency on MY-1675, and T005 stays intentionally blocked until the Owner supplies upload consent.
