# Data Model: TestFlight profile-name handoff

No persisted product data or schema changes.

## Ephemeral values

### Provisioning action output

| Field | Meaning | Lifetime |
|---|---|---|
| `SIGH_NAME` shared value | Display name of the profile produced by the most recent provisioning action | Until overwritten by the next action or lane end |
| action return / `SIGH_UUID` | UUID of the most recent profile | Diagnostic/action result only; never a display-name source |

### Captured target value

| Field | Source boundary | Consumers |
|---|---|---|
| app profile name | app action's current `SIGH_NAME`, captured before widget action | app archive specifier and app export mapping |
| widget profile name | widget action's current `SIGH_NAME`, captured after widget action | widget archive specifier and widget export mapping |

## Invariants

- Each captured name is present and non-blank.
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
- fabricated target-derived environment-key reads;
- UUID, fixed-name, or cross-target fallback.

Every invalid state terminates before `build_app`.
