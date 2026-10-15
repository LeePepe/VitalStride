# Data Model: TestFlight profile-name handoff

No persisted product data or schema changes.

## Ephemeral values

### Provisioning action output

| Field | Meaning | Lifetime |
|---|---|---|
| `ENV["SIGH_NAME"]` | Environment-backed display name emitted by Sigh for the current call when present | Stale-capable until explicitly neutralized or overwritten |
| lane-context `SIGH_NAME` shared value | Display name conditionally published by the provisioning action when the environment-backed name is present | Stale-capable until explicitly neutralized or overwritten |
| action return / `SIGH_UUID` | UUID of the most recent profile | Diagnostic/action result only; never a display-name source |

### Captured target value

| Field | Source boundary | Consumers |
|---|---|---|
| app profile name | both shared name locations neutralized; app action's current lane-context `SIGH_NAME` captured immediately before widget action | app archive specifier and app export mapping |
| widget profile name | both shared name locations neutralized again; widget action's current lane-context `SIGH_NAME` captured immediately after its action | widget archive specifier and widget export mapping |

## Per-call transition

For each target independently: neutralize the environment-backed name and lane-context name → invoke the real provisioning action → immediately capture the lane-context name into a target-local value → validate that current-call value before allowing the next target or build boundary.

## Invariants

- Each captured name is present and non-blank.
- Each captured name has provenance from its exact current invocation; neither stale-capable shared location may satisfy a missing output.
- App and widget names are distinct.
- A later shared-value overwrite cannot change the earlier captured app value.
- UUIDs never substitute for display names.
- Captured names are opaque and shell-safe at the archive boundary.
- No value is persisted, logged as credential material, or written to release state.

## Invalid states

- missing/blank app name;
- missing/blank widget name;
- equal app/widget names;
- delayed reads that observe only the widget value;
- stale environment or lane-context names surviving a no-name action and being accepted as current output;
- fabricated target-derived environment-key reads;
- UUID, fixed-name, or cross-target fallback.

Every invalid state terminates before `build_app`.
