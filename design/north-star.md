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
