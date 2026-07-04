# ADR-0008: DesignKit — One Seed-Based Design System Package

**Status**: Accepted
**Date**: 2026-07-02
**Deciders**: tianpli (project owner)

## Context

VitalStride spans three platforms (iOS / macOS / watchOS) and a growing surface of
custom UI — dashboard cards, metric tiles, sparklines, ring gauges, status pills.
Two problems had started to surface:

1. **Visual drift** — colors, corner radii, spacing, and type sizes were chosen
   per-view. The same "card" looked slightly different across screens, and dark-mode
   values were hand-tuned case by case. There was no single source of truth for the
   look of the app.
2. **No re-theming path** — changing the accent/brand color meant a find-and-replace
   across dozens of literals, with no guarantee neutrals and semantic (success /
   warning / danger) colors stayed consistent.

`VitalUI` already exists, but it holds *functional* shared components (error views,
snackbars, haptics) — not a design language. We wanted the visual system to be a
distinct, compiler-enforced boundary with its own tokens, not more helpers bolted
onto `VitalUI`.

We also maintain a parallel design-system web port. Keeping the two visually aligned
requires **the same color math on both sides**, not two hand-maintained palettes.

## Decision

Introduce **`DesignKit`**, a standalone local SPM package at `Packages/DesignKit/`,
as the **one** design language for all VitalStride app targets.

### Core idea: one seed color → the whole primary token set

- `makePrimaryPalette(seed:isDark:)` derives the full light/dark primary palette from
  a **single seed color**. Re-theming = pass a different seed. No forked language,
  no second palette.
- `chartPalette(seed:isDark:)` derives an 8-stop categorical chart ramp from the same
  seed.
- **Neutral and semantic palettes are FIXED** — they do not vary with the seed. Success
  is green, danger is red, regardless of brand color. This is the non-negotiable
  invariant that keeps meaning stable across themes.
- The seed math mirrors the design-system web port so both platforms stay aligned.

### Structure (two intra-layer roles)

| Role | Files | Contents |
|---|---|---|
| Types | `Color/ColorSystem.swift`, `Color/Theme.swift` | `Seed`, `PrimaryPalette`, `Neutrals`, `Semantic`, `Theme`, `Radius`, `Space`, `TypeScale` |
| UI | `Components/Components.swift`, `Components/DashboardView.swift` | `Card`, `CardInner`, `Metric`, `Sparkline`, `RingGauge`, `StatusPill`, `SectionHeader`, `DashboardView` |

`Theme` composes the three color layers + radius/space/type scales and is injected via
`EnvironmentValues`; components consume tokens from the environment rather than
hardcoding values.

### Registration

- Registered in `project.yml` under `packages:` and added as a dependency of the three
  app targets (iOS / macOS / watchOS), same level as `VitalUI`. Not added to
  `VitalStrideWidgets` (extension-only) or `VitalStrideTests`.
- `DesignKit` has **no local package dependencies** (`depends_on: []`) — pure SwiftUI +
  Foundation, like `TelemetryKit`.

## Consequences

### Positive
- One place defines the look; visual drift is caught by "does it use a `Theme` token?".
- Re-theming is a one-line seed change; neutrals/semantics can't accidentally shift.
- Compiler-enforced boundary — app code can't reach into ad-hoc color constants.
- Same seed math as the web port → cross-platform visual parity is maintainable.
- Pure value-type tokens + `Sendable` fit Swift 6 strict concurrency cleanly.

### Negative
- A second UI-adjacent package alongside `VitalUI`. The split (design language vs
  functional components) must stay clear or the two will blur.
- Existing hand-styled views must be migrated to tokens to realize the benefit;
  until migrated, two styling systems coexist.
- Seed-derived palettes need snapshot/parity tests to prevent silent math regressions
  (current `ColorSystemTests` covers palette derivation and the fixed-semantic invariant).

### Trade-offs accepted
- Kept `DesignKit` separate from `VitalUI` rather than merging — the boundary is worth
  the extra package. `VitalUI` may eventually consume `DesignKit` tokens; that is a
  future decision, not made here.
- Did not adopt a third-party design-token tool; the seed-function approach is small,
  auditable, and shared with the web port by hand.

## Implementation references

- `Packages/DesignKit/Package.swift`
- `Packages/DesignKit/Sources/DesignKit/Color/ColorSystem.swift` (`Seed`, `makePrimaryPalette`, `chartPalette`, `Neutrals`, `Semantic`)
- `Packages/DesignKit/Sources/DesignKit/Color/Theme.swift` (`Theme`, `Radius`, `Space`, `TypeScale`)
- `Packages/DesignKit/Sources/DesignKit/Components/Components.swift`
- `Packages/DesignKit/Sources/DesignKit/Components/DashboardView.swift`
- `Packages/DesignKit/Tests/DesignKitTests/ColorSystemTests.swift`
- `Packages/DesignKit/CONTEXT.md` (layer frontmatter: red_lines / roles / test)
- `project.yml` (`packages:` + app-target dependencies)

## Revisit triggers

- A second design language is genuinely needed (e.g. a sub-brand) — revisit the
  "one language, one seed" invariant before forking.
- `VitalUI` and `DesignKit` responsibilities start overlapping — decide whether to
  merge or draw a sharper line.
- The web port's seed math diverges — re-establish the shared-math contract or accept
  platform-specific palettes explicitly.
- Semantic colors need to vary by theme (they currently must not) — that breaks the
  core invariant and needs its own ADR.
