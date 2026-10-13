# Research: TestFlight in-run profile reuse

## Evidence

- Planning base: `e8cfc19d8d2ec3af64fdedc96eb8cd3d5c1dfd6b`.
- `fastlane/Fastfile` regenerates the Xcode project, fetches separate app and widget App Store profiles with `force: true` and installation enabled, then invokes `build_app`.
- Archive-time `xcargs` currently contains build number, team, and telemetry values but no target-specific provisioning-profile inputs.
- Export mapping reads the canonical Fastlane profile-name environment outputs but falls back to the provisioning action return values.
- `project.yml` keeps base signing Automatic, while the app and widget Release configurations are Manual and each contain a fixed profile display name.
- `.github/workflows/testflight.yml` is manual-only, checks out `main`, retains `force=false` by default, skips when no new commit exists unless forced, and never cancels an in-progress upload.
- `scripts/tests/test_testflight_freshness.py` already has four passing static tests for those workflow invariants. `scripts/test-repoinfra.sh` auto-discovers that module and the PR `Lint & policy` job invokes the complete gate.
- A real lane run queries ASC, can regenerate Developer Portal profiles, archives, uploads, distributes to internal groups, and advances the release tag. It is not a safe implementation test.

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

**Decision**: Deliver implementation through static, syntax, RepoInfra, XcodeGen, unsigned Release, and required PR evidence. Keep the real TestFlight run as a separate slice blocked by reviewed merge plus explicit Owner consent.

**Rationale**: The implementation can be fully reviewed without external mutation, while the issue's final operational outcome still receives a controlled new-runner proof. The non-Draft PR and `owner-review` label make the decision point visible before release.

## Decision 5: No ADR or domain-context change

**Decision**: Do not add an ADR or edit `CONTEXT.md`.

**Rationale**: This repair follows existing AppUI/RepoInfra ownership, XcodeGen truth-source, manual TestFlight, and PR-required decisions. It introduces no durable product terminology, dependency direction, public interface, or architecture reversal.

## No open clarification

MY-1606 revision 3 and the Team Lead handoff settle target behavior, compatibility, scope, PR constraints, and the Owner-consent boundary. No product or authority choice remains for implementation; only T004 stays intentionally blocked until the Owner supplies the required external consent.
