# Contract: Per-call TestFlight profile-name handoff

## Base and precedence

- Product base: `663054cb4e7f58459fd0caf6a0710f6e74f18bd0`.
- This contract supersedes only the fabricated/delayed profile-name source statements in `specs/026-testflight-profile-reuse/**`.
- The target-specific project interface from `026` and all workflow/release policy accepted by `027` remain unchanged.

## Sequential fetch contract

1. Fetch/install the app App Store profile with the existing API key, bundle ID, team, forced refresh, and installation behavior.
2. Before any widget fetch, capture the current real Fastlane shared profile name for the app.
3. Fetch/install the widget App Store profile with its existing bundle ID and the same preserved options.
4. Immediately capture the current real Fastlane shared profile name for the widget.
5. Validate both values before `build_app`.

## Source contract

- Supported name source: `lane_context[SharedValues::SIGH_NAME]` from the real provisioning action.
- Action UUID return is not a name.
- Target-derived lowercase `sigh_*_profile-name` keys are forbidden production reads and forbidden diagnostic authority.
- Fixed display names, a second lookup, and cross-target fallback are forbidden.

## Validation contract

- Nil and whitespace-only values are invalid.
- Equal app/widget names are invalid.
- Invalid state raises the existing Fastlane user-facing error before archive, upload, distribution, or release-marker mutation.
- Error text identifies the target and supported shared output without credentials, key material, certificates, keychain values, UUIDs, or profile contents.

## Consumer contract

| Target | Archive input | Export mapping |
|---|---|---|
| `VitalStride` | `VITALSTRIDE_APP_PROFILE_SPECIFIER` receives the shell-safe captured app name | `com.leepepe.vitalstride` receives the same app variable |
| `VitalStrideWidgets` | `VITALSTRIDE_WIDGET_PROFILE_SPECIFIER` receives the shell-safe captured widget name | `com.leepepe.vitalstride.widgets` receives the same widget variable |

No global profile override is added. `project.yml` remains unchanged.

## Real-action regression contract

The fixture:

- loads installed Fastlane/Sigh and the repository Fastfile;
- invokes the real provisioning-profile action;
- replaces `Sigh::Manager.start`, not the action;
- publishes distinct names and UUIDs for two sequential calls;
- proves the scalar shared name changes per call while the first target's captured value survives;
- proves missing, blank, and equal names stop before build/upload;
- proves shell-safe target mapping and exact-variable export reuse;
- prohibits fabricated convention reads in production `fastlane/**` and `scripts/**`;
- restores environment and lane context after each case;
- performs no network, signing, upload, distribution, workflow dispatch, marker mutation, or secret read.

## Compatibility contract

- Preserve forced installed fetches, team/bundle identity, manual Release signing, Automatic base/Debug signing, build numbering, telemetry inputs, upload/distribution, classifier/orchestration, concurrency, and marker behavior.
- Preserve all existing tests and assertions.
- Change only `fastlane/Fastfile`, `scripts/tests/test_testflight_packaging.rb`, and minimal mandatory wiring in `scripts/test-repoinfra.sh`.
