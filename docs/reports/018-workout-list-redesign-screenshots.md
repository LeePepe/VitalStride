# 018 · Workout list redesign — Design gate evidence (MY-1359)

**Status**: Pre-merge design gate (round-2, folded from MY-1360)
**Scope**: `WorkoutListView` + `HealthKitWorkoutRowView` + new `WorkoutSourceBadge` / `WorkoutListStateBanner`
**Spec**: `specs/018-workout-list-watch-healthkit-redesign/spec.md`
**Sub-issue**: MY-1361 (implementation of MY-1359)

## Purpose

MY-1359 replaces the two-section "VitalStride 训练 + Apple 健康训练" split with a single
`startDate`-descending timeline; every row carries a `WorkoutSourceBadge`; HealthKit rows carry
`avg HR`; the four load states (loading / failed / unauthorized / empty) render distinct UI. This
report is the pre-merge design-gate evidence bundle: before/after captures, load-state captures,
Dynamic Type + accessibility notes.

## Reproduction evidence (fixture-based)

The presentation issue is not a data-plane bug. `VitalStrideTests/WorkoutListRenderingTests.swift`
seeds three `HealthWorkoutRecord` fixtures (one `.appleWatch`, one `.iPhone`, one
`sourceDeviceKind == nil`) and asserts:

1. `WorkoutListMerger.merge` produces a **single** interleaved unified array
   (baseline: `unified.count == 3`, `dedupCount == 0`).
2. `WorkoutListView.visibleWindow` keeps every HealthKit row and caps App rows at the paging limit
   (baseline: `hkVisible.count == 4` even when `appLimit == 1`).
3. `UnifiedWorkout.sourceDeviceKind` surfaces `.appleWatch` / `.iPhone` / `nil` correctly for the
   badge to render (Apple Watch fixture → Apple Watch badge).
4. `WorkoutSourceBadge.accessibilityLabel(...)` yields distinct, non-empty labels for every
   variant the combined row `.accessibilityLabel` embeds.

That test file is the "red → green" evidence anchor. See spec §3 Validation plan.

## Screenshots

Screenshots for the design gate are captured in Xcode preview mode (SwiftUI Previews on the
iPhone 16 simulator, iOS 18) since simulator-side fixture injection into HealthKit is not
supported. Fixture Preview set is defined in the `#Preview` blocks of
`WorkoutSourceBadge.swift`, `WorkoutListStateBanner.swift`, and `WorkoutListView.swift`.

### Comparison matrix (before / after)

| # | Preview                                                    | Scheme  | Dynamic Type      | Notes |
|---|------------------------------------------------------------|---------|-------------------|-------|
| 1 | List with one mixed App + HK section (Apple Watch fixture) | Light   | `.large`          | Before: App / HK split into two visually-weaker sections. After: single section, badges visible, avg HR chip on HK rows. |
| 2 | Same as #1                                                 | Dark    | `.large`          | Verifies theme.neutrals.inner + border tokens carry through dark mode. |
| 3 | Same as #1 (fixture unchanged)                             | Light   | `.accessibility3` | Verifies `Large` typography scaling — activity type / duration / avg HR stay legible; badge glyph stays visible. |
| 4 | Same as #1                                                 | Dark    | `.accessibility3` | Dark + Large combined regression. |
| 5 | State banner – `.loading`                                  | Light   | `.large`          | Distinct spinner + subtitle. |
| 6 | State banner – `.failed`                                   | Light   | `.large`          | Warning glyph in `theme.warning`. |
| 7 | State banner – `.unauthorized`                             | Light   | `.large`          | Lock glyph in `theme.primary.primary` + "Open Settings" button (≥44×44pt). |
| 8 | State banner – `.unauthorized`                             | Dark    | `.accessibility3` | Verifies subtitle wraps, CTA hit target holds. |

### Capture instructions (deterministic, no live HealthKit)

The captures below are rendered from `Prototype/Sources/Prototype/WorkoutListPrototype.swift`
via the `WorkoutListShotExporter` SPM executable, which uses SwiftUI `ImageRenderer` at 2× scale
against a `Theme(seed: .teal, neutral: .slate, isDark: …)`. That path is deterministic (no
simulator, no live HealthKit) and can be re-run any time to regenerate the fixtures.

```bash
swift run --package-path Prototype WorkoutListShotExporter \
  docs/reports/018-workout-list-redesign-screenshots
```

The prototype target reconstructs the same visual composition as the production `WorkoutListView`
using DesignKit tokens only (Space / Radius / TypeScale / Theme neutrals) — no hardcoded colours,
radii, or font sizes. It deliberately does NOT import `VitalStride` / `VitalModels` /
`HealthKitService` so the render loop stays isolated from SwiftData + HealthKit.

### Captures (MY-1361 round-2 evidence)

Rendered outputs live beside this file under
`docs/reports/018-workout-list-redesign-screenshots/`.

**Mixed App + HK (Apple Watch fixture)** — required ≥4 light/dark × normal/Large captures:

| # | File | Scheme | Dynamic Type | Content |
|---|------|--------|--------------|---------|
| 1 | `01-list-mixed-light-large.png` | Light | `.large` | Apple Watch running row + iPhone walking row + App push-day row; avg HR chip on both HK rows. |
| 2 | `02-list-mixed-dark-large.png` | Dark | `.large` | Same fixture — verifies `theme.neutrals.inner` + border tokens carry through dark mode. |
| 3 | `03-list-mixed-light-accessibility.png` | Light | `.accessibility1` | Verifies Dynamic Type scaling — badge glyph, avg HR chip, and subtitle stay legible. |
| 4 | `04-list-mixed-dark-accessibility.png` | Dark | `.accessibility1` | Dark + Large combined regression. |

**Load-state banners + empty state**:

| # | File | State | Notes |
|---|------|-------|-------|
| 5 | `05-banner-loading-light-large.png` | `.loading` | Spinner + "Loading workouts" subtitle. |
| 6 | `06-banner-failed-light-large.png` | `.failed` | Warning glyph in `theme.warning`. |
| 7 | `07-banner-unauthorized-light-large.png` | `.unauthorized` | Lock glyph + "Open Settings" button (≥ `Space.minTapTarget` = 44 pt). |
| 8 | `08-banner-unauthorized-dark-accessibility.png` | `.unauthorized` | Dark + `.accessibility1` — subtitle wraps, CTA hit target holds. |
| 9 | `09-empty-light-large.png` | (empty) | `ContentUnavailableView`-shaped empty state; owned by `WorkoutListView`, not the banner. |

### Design-token compliance (MY-1361 P0 — DesignKit red line)

Every metric in the captured views resolves to a DesignKit token. Concretely:

- `WorkoutSourceBadge` badge chrome: `Space.hair` (icon↔text), `Space.inline` (horiz padding),
  `Space.chipVertical` (vert padding), `Radius.badge` (corner), `TypeScale.meta` (label),
  `theme.neutrals.text2` / `theme.neutrals.inner` / `theme.neutrals.border`.
- `WorkoutListStateBanner`: `Space.gap` (outer padding + icon/text gap), `Space.hair` (title↔subtitle
  gap), `Space.minTapTarget` (button min height), `Radius.inner` (banner corner), `TypeScale.title` /
  `TypeScale.body` (title / subtitle / CTA font).
- Icon container in `.loading`: `Space.minTapTarget / 2` (deliberately half of the tap-target token
  to align with the ProgressView optical size).

No literal `.padding(12)` / `.font(.subheadline)` / `RoundedRectangle(cornerRadius: 10, ...)` remain
in either the badge or the banner. New DesignKit tokens introduced this round to close the gap:
`Radius.badge`, `Space.hair`, `Space.inline`, `Space.chipVertical`, `Space.minTapTarget`.

## Design-review checklist (self)

| Check                                              | Result | Evidence |
|----------------------------------------------------|--------|----------|
| Single unified section (no App/HK partition)        | Pass   | `WorkoutListView.body` → `visible` fed straight into one Section; `WorkoutListRenderingTests.visibleWindowInterleavesUnified` |
| Source badge on every row (App + HK variants)       | Pass   | `WorkoutRowView` appends `WorkoutSourceBadge(isApp: true)`; `HealthKitWorkoutRowView` appends `WorkoutSourceBadge(kind:sourceName:isApp:false)` |
| avg HR chip on HK rows when `averageHeartRate != nil` | Pass  | `HealthKitWorkoutRowView.avgHeartRateChip` gated by optional binding; hidden otherwise |
| Four distinct states                                | Pass   | `WorkoutListStateBanner.LoadState` (loading/failed/unauthorized) + `ContentUnavailableView` empty state in `WorkoutListView.body` |
| "Open Settings" deep-link with ≥44pt hit target     | Pass   | `Button` in `WorkoutListStateBanner` uses `.frame(minHeight: 44)` + `.buttonStyle(.borderedProminent)` + horizontal padding |
| Localisation (Localizable.xcstrings, en/zh-Hans)    | Pass   | 25 new keys added to `VitalStride/Resources/Localizable.xcstrings` under `workout_list.*` |
| Decorative icons `.accessibilityHidden(true)`       | Pass   | Badge glyph + heart glyph + banner glyphs all hidden |
| Combined row `.accessibilityLabel` includes badge   | Pass   | `HealthKitWorkoutRowView.accessibilityDescription` calls `WorkoutSourceBadge.accessibilityLabel(...)` |
| Banner CTA has own `.accessibilityLabel` + hint     | Pass   | `WorkoutListStateBanner` "Open Settings" button carries both |
| Previews cover light/dark + Dynamic Type variants   | Pass   | `WorkoutSourceBadge`: 2 previews; `WorkoutListStateBanner`: 6 previews (3 states × 2 schemes); `WorkoutListView`: existing preview retained |
| Privacy red line (avg HR / kcal / distance not logged) | Pass | `WorkoutListView.loadHealthKitWorkouts` logs only counters (`count`, `total`, `dedupCount`) and the state discriminator; no per-record HR/energy/distance values reach `logger` or `signposter`. Test: `HeartRatePrivacyLoggingTests` continues to guard the shared code path. |
| pbxproj unchanged                                   | Pass   | Only source, resource, and doc files touched; XcodeGen owns the pbxproj (Constitution §IV). |

## Follow-ups (out of this task)

- Snapshot testing (SnapshotTesting SPM) has never been onboarded in this repo; snapshots stay
  Preview-based for now. If the design reviewer wants a stronger regression net, that's a
  separate infra task.
- Live-device capture with a real Apple Watch account remains manual; the fixture-based
  reproduction proves the presentation issue independently.
