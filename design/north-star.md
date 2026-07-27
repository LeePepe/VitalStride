# VitalStride — Visual North-Star

> The visual target the `design-reviewer` scores against. Every rule is concrete and
> checkable. VitalStride already ships **DesignKit** (seed-color tokens + Card / Metric /
> Sparkline / RingGauge / StatusPill / SectionHeader) — this north-star is the standard the
> app adopts by wiring DesignKit into every screen. Not a second design language.

## 0. One-line principle

> 留白舍得给，层级拉得开，数字配上图，配色管得住 — a **health dashboard**, not a text report.
> One seed themes every screen; semantic green=good / red=bad never moves.

Faults this redesign fixes (from diagnose — flagship `OverviewView.swift`):
| Fault | Fix |
|---|---|
| DesignKit built but imported by 0/101 views; every screen raw SwiftUI | wire `.designTheme(...)` at app root; screens consume `@Environment(\.theme)` + DesignKit components |
| `.padding()`-only → full-bleed, stretches sparse on Mac/iPad | max content width ~1200pt, centered |
| `.regularMaterial` cards, no elevation tiers | luminance tiers (bg < card < inner) + 1px hairline border, no shadows |
| KPIs are text + ▲▼ arrows, no charts | Sparkline (area+line) / RingGauge beside every number |
| `.headline`/`.subheadline`/`.caption` only, non-tabular numbers | ≥3 deliberate type levels; all numbers tabular/rounded |
| grey `.secondary`/`.tertiary` status text | colored `StatusPill` |
| hardcoded `Color.blue` / systemGray per screen | seed-derived primary + fixed neutral/semantic tokens only |

North-star references: **Apple Health / Fitness** (data density + rings), **Linear** (elevation,
restraint, type hierarchy), **Vercel dashboard** (KPI grid).
Design philosophy: Apple-native restraint as the base + modern-dashboard density. Health-app warmth.

## 1. Layout & grid
- **Max content width:** `Space.contentMaxWidth` (1200pt), centered. On iPhone it's a no-op; on Mac/iPad it kills stretch.
- Page horizontal padding: 20 (iOS) / 24 (Mac). Vertical top: 20.
- Section spacing: 24. Section header → first item: 12 (`Space.gap`).
- Health KPI grid: `LazyVGrid(.adaptive(minimum: 160, maximum: 260), spacing: 12)` — 2-up on iPhone, more on Mac.
- Card gap within a group: 12.

## 2. Spacing scale (only these)
`2 4 8 12 16 20 24 28 32` — prefer `Space.gap` (12) and `Space.cardPadding` (16) from Theme.

## 3. Typography — ≥3 levels (use DesignKit `TypeScale`)
| Role | Token | Use |
|---|---|---|
| Nav title | `.largeTitle.bold()` (system nav) | screen title |
| KPI number | `TypeScale.display` (26, semibold, **monospacedDigit**) | the focal number |
| Card title | `TypeScale.title` (16, semibold) | card header |
| Body | `TypeScale.body` (14) | prose |
| Section label | `SectionHeader` → `TypeScale.meta` semibold **UPPERCASE**, `text2` | group headers |
| Meta / unit | `TypeScale.meta` (12), `text3` | units, timestamps |
| Pill | `TypeScale.meta` medium | status badges |

Rules: every KPI number is `.monospacedDigit()`; ≥3 distinct sizes/weights visible per screen.

## 4. Color — restrained, token-only
- **Never** hardcode hex/`Color.blue`/systemGray in a view. Only `theme.primary.*`, `theme.neutrals.*`, `theme.success/warning/danger`, `theme.chart(i)`.
- Body text `neutrals.text1`; secondary `text2`; never put primary content in `text3`.
- ≤1 primary accent anchor per card (the seed). Charts use `theme.chart(i)` (seed-hued family).
- Status semantics fixed: success→green, warning→orange, danger→red.
- **Status pill** (`StatusPill`): `color.opacity(0.16)` fill + full-saturation text, Capsule, h8/v2.
- **Categorical/functional distinction (workout split badges, settings icon tiles, etc.)** walks the seed hue in a **tight blue-ward band** at stepped brightness (`categoryColor(i:theme:)`) — it must **never** enter the green/amber/red arc, so semantic green=good / red=bad stays unambiguous. Distinction comes from brightness, not from leaving the seed family.

## 5. Card & elevation — flat luminance tiers (ONE scheme, no shadows)
- Page bg = `neutrals.bg` (L0). Card = `neutrals.card` (L1). Nested = `neutrals.inner` (L2).
- Every card: 1px `neutrals.border` hairline. Radius `Radius.card` (14) / `Radius.inner` (10), continuous.
- No `shadow()`, no `.regularMaterial`/`.ultraThinMaterial` as card bg. Elevation reads from luminance + border only.

## 6. Health KPI card structure
`SectionHeader`/label (uppercase, text2) → big number (`TypeScale.display`) + unit (meta, text3) →
optional `StatusPill` or delta → **Sparkline or RingGauge**. Ratio/goal metrics (sleep vs target,
activity ring) use `RingGauge`; time-series (steps, weight, HR trend) use `Sparkline`.

## 7. Data-viz
- **Sparkline:** DesignKit area(gradient)+line, ~36pt, axes hidden. Color = `theme.chart(i)` or the metric's semantic color.
- **RingGauge:** trimmed circle, start dot, `%` center text visible even at low value.
- Every screen with numbers shows at least one chart — a screen of pure numbers + arrows fails review.

## 8. Prose / AI-insight card
Header row: `StatusPill` (tone) + title (`TypeScale.title`) + timestamp (meta, text3). Body: DesignKit
`Card` with `Space.gap` rhythm, row dividers = `neutrals.border`, left status via pill/dot — never grey text alone.

## 9. Platform notes
- **iOS**: primary target. 2-up KPI grid, `NavigationStack` title large.
- **Mac**: same DesignKit; max-width centering does the heavy lifting; denser grid.
- **Watch**: DesignKit tokens (color/type) apply; components simplify to single-column Metric + tiny Sparkline. No max-width.

## 10. Acceptance checklist (reviewer scores /35)
- [ ] Every screen imports DesignKit + reads `@Environment(\.theme)` (0 raw `Color.blue`/systemGray/material-card)
- [ ] Max content width, not stretched
- [ ] Health KPIs = independent cards in adaptive grid, columnar
- [ ] Sparkline/ring next to each number
- [ ] Flat luminance-tier elevation, consistent, 1px hairline
- [ ] ≥3 type levels; numbers tabular
- [ ] Status as colored pills, not grey text
- [ ] Token-only color (no hex in views)
- [ ] One seed re-themes all; swapping seed proven in snapshots

## 11. Workout Numeric Keyboard

> Applies to the custom in-app numeric keyboard rendered inside the ActiveWorkout weight / reps
> input (`VitalStride/Sources/WorkoutNumericKeyboard.swift` +
> `VitalStride/Sources/NumericKeypad.swift`). Height budget: **iPhone ≤ 260pt, iPad ≤ 280pt**;
> three columns (left function keys · center digit grid · right presets + Done). Every rule below
> is checkable against `Prototype/Sources/Prototype/WorkoutKeyboardPrototype.swift` and the
> exported shots in `design/prototype-shots/keyboard-{iphone,ipad}-{light,dark}.png`.

### 11.1 Radius (three tiers)
| Role | Token | Value |
|---|---|---|
| Done key | `Radius.inner` | 10pt (`.continuous`) |
| Preset keys | `Radius.inner` | 10pt (`.continuous`) |
| Function keys | `Radius.inner` | 10pt (`.continuous`) |
| Digit keys | `Radius.inner` | 10pt (`.continuous`) |
No hardcoded radius. All keys share `Radius.inner` for one coherent inner rhythm; the outer
keyboard host has no card radius because it fills the inputView bounds.

### 11.2 Spacing (all off the `Space.*` scale)
| Role | Value | Notes |
|---|---|---|
| Outer padding (all sides) | `Space.cardPadding` (16) | keyboard-to-frame air |
| Column gap (left ↔ center ↔ right) | `Space.gap` (12) | between the three logical columns |
| Row spacing inside a column | 8 | scale value; sits between `Space.gap` (12) and 4 |
| Digit grid column spacing | 8 | matches row spacing → square cell rhythm |
| Function key `minHeight` | 44 | Apple ≥44pt hit target — red line |
| Preset key `minHeight` | 44 | Apple ≥44pt hit target — red line |
| Done key `minHeight` | 44 | Apple ≥44pt hit target — red line |
| Digit key `minHeight` | 52 | 3×4 grid; larger for numeric primary focus |
| Left / right column width | 76pt | ≤72–76 fits both iPhone and iPad within budget |

### 11.3 Color — three-tier hierarchy (Done > preset > inner keys)
| Role | Fill | Foreground | Rationale |
|---|---|---|---|
| **Done** (primary CTA) | `theme.primary.primary` | `theme.primary.onPrimary` | one seed-anchor per surface |
| **Preset keys** (15-20 / 8-12 / 4-6) | `theme.primary.primarySubtle` | `theme.primary.primaryText` | seed family, subordinate to Done |
| **Function keys** (pyramid / drop / uni / copy) | `theme.neutrals.inner` | enabled: `theme.neutrals.text2`; disabled: `theme.neutrals.text3` | recessed, non-primary |
| **Digit keys** (0-9, decimal) | `theme.neutrals.inner` | `theme.neutrals.text1` **(RED LINE)** | numbers must never fall to text2/text3 — audit P0 must not recur |
| **Delete key** (`⌫`) | `theme.neutrals.inner` | `theme.neutrals.text2` | destructive, softened one step |
| **Keyboard background** | `theme.neutrals.bg` | — | matches page L0 luminance tier |

The three-tier color scheme reads left-to-right: **primary → primarySubtle → inner**. No hex,
no `Color.*`, no `.systemGray*`. Semantics fixed: never map preset to `primary` (they are not
the final commit) and never map Done to `primarySubtle` (it is the sole commit).

### 11.4 Typography
| Role | Font | Notes |
|---|---|---|
| Digit key label | `TypeScale.title` (16, semibold) + `.monospacedDigit()` | numbers must be tabular |
| Delete key label | `TypeScale.title` (16, semibold) | glyph, no digit alignment needed |
| Preset key label | `TypeScale.body` (14, semibold) + `.monospacedDigit()` | range labels like "15-20" |
| Done key label | `TypeScale.title` (16, semibold) | primary CTA |
| Function key text label | `TypeScale.meta` (12, medium) + `.minimumScaleFactor(0.8)` + `.lineLimit(1)` | "Uni/Total" / "Copy" |
| Function key symbol | `.title3` (system) + medium weight | SF Symbols for pyramid/drop |
Every digit-containing key **must** call `.monospacedDigit()` — no exceptions.

### 11.5 foregroundStyle — key-by-key token map (red line)
- digit keys → `theme.neutrals.text1` **(RED LINE — audit P0: numbers must not fade to text2/text3)**
- delete key → `theme.neutrals.text2`
- function key (enabled) → `theme.neutrals.text2`
- function key (disabled) → `theme.neutrals.text3`
- preset key → `theme.primary.primaryText`
- done key → `theme.primary.onPrimary`

### 11.6 Reference screenshots
- Light + iPhone: `design/prototype-shots/keyboard-iphone-light.png`
- Dark + iPhone: `design/prototype-shots/keyboard-iphone-dark.png`
- Light + iPad: `design/prototype-shots/keyboard-ipad-light.png`
- Dark + iPad: `design/prototype-shots/keyboard-ipad-dark.png`
Baseline (before) for the same three-column layout lives under
`design/keyboard-current-shots/`.

### 11.7 Non-visual constraints (context — do not "improve" in Stage 2)
- **Interaction contract frozen** (audit + parent MY-1342): `SetField` / `LeftKeyAction` /
  `PresetRepBucket` shapes and the four callback surfaces are red lines; visual redesign must
  not change them.
- **Detached UIKit `inputView`**: production keyboard is a `UIView` hosted via
  `UIHostingController`; theme is injected explicitly by `WorkoutNumericKeyboard.resolveTheme(isDark:)`
  because the SwiftUI `@Environment(\.theme)` does not propagate into the inputView tree. The
  Prototype does not carry this UIKit bridge and does not need to — but the eventual production
  port (Stage 4) does.
- **≥44pt hit target** for every keyboard key, `.isKeyboardKey` a11y trait retained, per-key
  a11y label retained.

