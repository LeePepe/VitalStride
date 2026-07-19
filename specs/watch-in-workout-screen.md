# Design Spec — watchOS In-Workout Screen (live HR + next set, **two-axis configurable**)

**For**: MY-1282 `[T002] [watchOS] Watch app 真实训练流程` (configuration is IN scope — user decision)
**Design system**: DesignKit (ADR-0008, seed-based) — no new palette, no hardcoded hex
**Scope gate**: ADR-0010 (watchOS live-HR training flow, narrow ADR-0002 exception) + §I privacy
**Register**: product (design serves the task) · Platform: watchOS (Apple HIG)
**Visual reference**: `specs/watch-in-workout-mockup.html` (4 layer presets, all states) — open in browser
**SwiftUI reference**: `specs/WatchInWorkoutView.prototype.swift`
**Status**: shaped via `/impeccable shape`, confirmed → hands to MY-1282

---

## 0. Scope notes the implementer MUST absorb (read first)

Three things here EXPAND the original ADR-0010 / MY-1282 envelope. All user-confirmed.

1. **Bidirectional workout-state sync, not just HR.** ADR-0010 specced HR **watch → iPhone**.
   Showing the next set + completing a set on the watch requires:
   - **iPhone → watch**: active workout plan (current exercise, its sets with target reps/weight,
     completion state) — pushed on session start + on every iPhone-side edit.
   - **watch → iPhone**: a `SetCompletedEvent` when the user taps the primary button.
   Co-designed with **MY-1281** (owns the WCSession contract). MY-1281 must grow a
   `WorkoutStateSnapshot` (iPhone→watch) + `SetCompletedEvent` (watch→iPhone). **Requires a
   one-line ADR-0010 addendum** (bidirectional, not HR-only).

2. **Two-axis configurability is IN MY-1282** (user chose "合进 MY-1282 一起做"). See §7. The
   iPhone→watch config payload (`WatchScreenConfig`) rides the same MY-1281 WC channel.

3. **One DesignKit token addition** (additive, does NOT fork the language → ADR-0008 holds):
   ```swift
   // DesignKit/Color/Theme.swift — TypeScale
   public static let metricXL = Font.system(size: 44, weight: .semibold).monospacedDigit()
   public static let metricXXL = Font.system(size: 64, weight: .semibold).monospacedDigit() // hrFocus preset hero
   ```
   `TypeScale.display` (26pt) is too small for a wrist HR hero. `metricXL` = the 3·2·1 hero;
   `metricXXL` = the hrFocus (2·1) preset's oversized hero. Both are additive scale steps read
   as tokens, never per-view `.system(size:)`. If DesignKit owners reject, fallback is a single
   DesignKit-owned watch modifier — but tokens are the right home.

---

## 1. Feature summary

While a strength session is active, the watch shows an at-a-glance screen whose **skeleton and
contents are user-configurable** along two orthogonal axes (§7):

- **Layer preset** — which tier skeleton (4 designed: `fullInfo` / `hrFocus` / `list` / `nextFocus`).
- **Module toggles** — within a preset, which info modules are shown.

Two elements are **locked on** in every preset/toggle combination: **live heart rate** (the screen's
reason to exist per ADR-0010) and the **primary action button** (the core interaction). Default =
`fullInfo` (3·2·1) with all modules on.

## 2. Primary user action

**Glance → read the configured data → tap the primary button between sets** (completes current set,
advances). Reading dominates; one tap is the only required interaction.

## 3. Design direction

- **Restrained**, dark-only. Scene: "A lifter mid-set, arm partly raised, glances at the wrist for
  ~1s under gym light to confirm heart rate and what's next." → dark, one hero, zero decoration.
- One seed accent (primary button + progress dots), semantic color for HR zone + connection state.
- Anchors: Apple **Workout** app, **Whoop** single-number glance, **Hevy/Gymshark** set rows.

## 4. The four Layer presets (axis A)

All fit one screen, no scroll; primary button locked bottom. Tier counts describe info density
top→bottom. See mockup for pixel-faithful renders.

### A. `fullInfo` — 3·2·1 (DEFAULT)
```
[ 时间  ·  ⏱时长  ·  ◔组数 ]        ← tier 1: session band, 3 items
[ ●128 BPM        Zone3 / 均峰 ]    ← tier 2: HR hero (left) + zone·avg/peak (right col)
[ 下一组 深蹲  8次×60kg  ●●◉○○ ]   ← tier 3: next-set block
[        完成这组 ✓        ]         ← locked action
```
Hero = `TypeScale.metricXL`. Densest; daily default.

### B. `hrFocus` — 2·1
```
[ ⏱时长  ·  ◔组数 ]                 ← tier 1: 2 items (clock off by default here)
[      ● 128       ]                ← tier 2: HR hero CENTERED, TypeScale.metricXXL (64pt)
[   Zone3 · BPM·均122   ]           ←         zone + secondary inline under it
[        完成这组 ✓        ]
```
Hero oversized, centered. next-set hidden by default. For cardio / HR-watching.

### C. `list` — 1·1·1·1
```
[ 时间  ·  ◔组数 ]
[ 心率     128 · Zone3 ]  ← each metric = one labeled row
[ 下一组   深蹲 8×60kg ]
[ 时长     24:18       ]
[ 均/峰    122 / 141   ]
[        完成这组 ✓        ]
```
Rows via a label→value pattern (mirrors Apple's multi-metric workout view). HR value in
`theme.success`/zone color per §6a. For reading everything at once.

### D. `nextFocus` — 1·2 (inverted)
```
[ ●128 Z3   ·   ⏱24:18 ]          ← tier 1: HR compressed to a band row
[   下一组  第3/5组                 ← tier 2: next-set ENLARGED as hero
     深蹲                            exercise TypeScale.title→big
     8次 × 60kg     ●●◉○○ ]         reps×weight ~24pt
[        完成这组 ✓        ]
```
HR shrinks to a top-band chip (dot + number + zone abbrev "Z3"); next-set is the hero. For
strength lifters who track weight/reps first.

## 5. Layout strategy & invariants (CRITICAL for MY-1282)

**Do NOT hardcode any one preset.** The screen body is:
```
VStack {
    ForEach(preset.tiers) { tier in
        ForEach(tier.enabledModules) { module in module.view(state) }
    }
    Spacer()                 // pushes button to bottom in every preset
    PrimaryActionButton()    // LOCKED, always present
}
```
- **Preset** = an ordered list of tiers; each tier = an ordered list of module ids + a layout hint
  (band / hero / row / block).
- **Module toggles** filter `enabledModules`.
- **Invariant 1 — one screen, no scroll**, every preset × every toggle combo. Verified at 41mm.
- **Invariant 2 — button locked bottom** via `Spacer()`; never scrolls off.
- **Invariant 3 — graceful collapse**: disabled modules removed from the list; siblings reflow
  (band re-justifies, HR right-column disappears if both `hrZone`+`hrAvgPeak` off, etc.).
- **Invariant 4 — two locks**: `heartRate` + `primaryAction` cannot be removed by any preset or toggle.

Emphasis ladder always: **HR (or next-set in nextFocus) hero ≫ secondary metrics > band meta**.
≥3 type levels; all numbers tabular.

## 6. Key states (orthogonal to preset — every preset renders all of these)

### 6a. Three HR connection states (never a bare `--`)

| State | Trigger | HR renders | Tokens |
|---|---|---|---|
| **NOT CONNECTED** | no session stream / WC unreachable | `StatusPill("未连接", .neutral)`; sub-line "开始训练以连接心率" `text3`; no fake digits | pill neutral = `text3` |
| **CONNECTED · NO DATA** | session active, awaiting 1st sample | pulsing dot (`text3`) + `···` in hero-font `text3`; `StatusPill("连接中", .primary)` | dot 0.35↔1.0 @1s |
| **CONNECTED · VALUE** | live sample | solid dot in zone color + value in hero-font `text1` + `StatusPill("Zone N", zoneTone)` | zone→tone below |

**HR zone → color** (semantic/chart tokens, never raw hex; computed on-device from HRR, spec 013):

| Zone | tone → color | dot |
|---|---|---|
| 1 recovery | `.neutral` → text3 | `theme.chart(5)` |
| 2 aerobic | `.primary` → seed | `theme.primary.primary` |
| 3 tempo | `.success` → #30D158 | `theme.success` |
| 4 threshold | `.warning` → #FF9F0A | `theme.warning` |
| 5 max | `.danger` → #FF453A | `theme.danger` |

### 6b. Other states
- **No plan / freeform**: next-set module → `StatusPill("自由训练", .neutral)` + "无预定计划"; button → "记录一组". (In presets where next-set is hidden, freeform just hides it.)
- **Last set of last exercise**: button → "完成训练"; next-set header → "最后一组 💪".
- **Rest timer running**: next-set slot swaps to rest countdown (`metricXL` `01:30` in `theme.primary.primary`); auto-reverts.
- **Session saving**: full-screen `ProgressView().tint(theme.primary.primary)` + "保存训练…".

### 6c. Always-On Display (AOD) — applies per-module to whatever the preset shows
- **Keep**: HR number, zone pill, next-set reps×weight, elapsed (legibility is AOD's point).
- **Dim**: `text1`→`text2`, `text2`→`text3`; pulse dot static @60% (no per-second animation in AOD);
  primary button → transparent + `theme.neutrals.border` outline (filled seed burns pixels).
- **Drop**: dot-array redraw, any motion, sub-labels.
- `@Environment(\.isLuminanceReduced)` gates it. HR must clear 4.5:1: `text2` (#B0B4BA) on bg
  (#111113) ≈ 7:1 ✓.

## 7. Configuration architecture (axis A + axis B, IN MY-1282)

Two orthogonal axes, configured on **iPhone**, pushed to watch via the MY-1281 WC channel.

### Axis A — Layer preset
`enum WatchLayoutPreset { case fullInfo, hrFocus, list, nextFocus }`. Default `.fullInfo`. Each
preset is a static description: `[Tier]` where `Tier = (layout: TierLayout, modules: [ModuleID])`.

### Axis B — Module toggles
`Set<ModuleID>` of enabled modules. Module ids + defaults:

| ModuleID | element | default | lockable |
|---|---|---|---|
| `clock` | 当前时间 | on (off in hrFocus) | toggle |
| `elapsed` | 训练时长 | on | toggle |
| `setsTotal` | 总组数 x/y | on | toggle |
| `heartRate` | HR hero | on | **LOCKED on** |
| `hrZone` | zone pill | on | toggle |
| `hrAvgPeak` | 均/峰 HR | on | toggle |
| `nextSet` | 下一组 | on (off in hrFocus) | toggle |
| `setDots` | 组进度点阵 | on | toggle |
| `primaryAction` | 完成按钮 | on | **LOCKED on** |

### Storage & transport
- **`WatchScreenConfig { preset, enabledModules }`** — app config, **NOT health data** (carries no
  HK values) → normal store; may CloudKit-sync with training data (not `.none`). Re-verify §I when built.
- Pushed watch-bound as a `WatchScreenConfig` payload on the MY-1281 **application-context**
  channel (low-churn, latest-wins) alongside `WorkoutStateSnapshot`.
- **iPhone settings UI**: preset picker (4 options, visual thumbnails ideal) + module toggle list
  with the 2 locked rows shown pinned/disabled. Reuses DesignKit form components. Lives in iOS
  Settings → 训练 → 手表训练屏.
- **Watch fallback**: stale/absent config → default (`fullInfo`, all on). Never blank.
- **Config arrives mid-workout** → re-layout with crossfade (honor Reduce Motion).

## 8. Content (all via `String(localized:)` → xcstrings; no hardcoded Chinese in code)

| Key | zh |
|---|---|
| `watch.hr.notConnected` | 未连接 |
| `watch.hr.connecting` | 连接中 |
| `watch.hr.hint.start` | 开始训练以连接心率 |
| `watch.hr.zone` | Zone %lld |
| `watch.hr.zoneShort` | Z%lld |
| `watch.hr.avgPeak` | 均 %lld · 峰 %lld |
| `watch.nextSet.label` | 下一组 |
| `watch.nextSet.freeform` | 自由训练 |
| `watch.nextSet.noplan` | 无预定计划 |
| `watch.nextSet.last` | 最后一组 💪 |
| `watch.nextSet.progress` | 第 %lld / %lld 组 |
| `watch.set.format` | %lld次 × %@ |
| `watch.band.sets` | %lld/%lld |
| `watch.list.hr` / `.nextSet` / `.duration` / `.avgPeak` | 心率 / 下一组 / 时长 / 均/峰 |
| `watch.action.completeSet` / `.logSet` / `.finish` | 完成这组 / 记录一组 / 完成训练 |
| `watch.controls.pause` / `.end` | 暂停 / 结束训练 |
| `watch.saving` | 保存训练… |
| **iPhone settings** | |
| `settings.watchScreen.title` | 手表训练屏 |
| `settings.watchScreen.preset` | 布局 |
| `settings.watchScreen.preset.fullInfo` / `.hrFocus` / `.list` / `.nextFocus` | 全信息 / 心率优先 / 列表 / 下一组优先 |
| `settings.watchScreen.modules` | 显示模块 |
| `settings.watchScreen.locked` | 必选 |

Ranges: HR 40–210 (3-digit hero); reps 1–30; weight 0–300kg; sets 1–20/exercise, 1–15 exercises;
duration to 3–4h (`HH:MM`, `mm:ss` <1h); clock 24h `HH:MM`.

**Privacy §I**: HR value display-only, NEVER logged. Log only `hr_state`, `zone=N`, sample count —
never the BPM integer. `WatchScreenConfig` carries no health values.

## 9. Token cheat-sheet

| Element | Font | Color |
|---|---|---|
| HR hero (fullInfo/list/nextFocus-band) | `TypeScale.metricXL` (44) | `text1` / zone dot |
| HR hero (hrFocus) | `TypeScale.metricXXL` (64) | `text1` |
| "BPM" / units | `TypeScale.meta` | `text3` |
| Zone pill | `StatusPill(tone:)` | per §6a |
| Pulse dot | 8pt circle | zone color |
| avg/peak | `TypeScale.meta` | `text3`, values `text2` |
| clock (band) | `TypeScale.meta` | `text1` (brightest of band) |
| elapsed/sets (band) | `TypeScale.meta` | `text2`, icons `text3` |
| next-set label | `SectionHeader` | `text2` |
| exercise name | `TypeScale.body` (nextFocus: bigger) | `text1` |
| reps×weight | `TypeScale.title` (nextFocus: ~24) | `text1` tabular |
| set dots | 8pt circles | done/cur `primary`, todo `border` |
| list row label | `TypeScale.meta` uppercase | `text3` |
| list row value | `TypeScale.title` | `text1` (HR: zone color) |
| primary button | `TypeScale.title` | fill `primary.primary`, label `primary.onPrimary`, 44pt tall, `Radius.inner` |
| screen bg / block bg | — | `neutrals.bg` / `neutrals.inner` |
| padding | — | `Space.cardPadding` H, safe-area top |

## 10. Recommended impeccable references during build
- `reference/ios.md` — HIG (safe area, 44pt targets, SF Symbols, Reduce Motion, AOD).
- `reference/harden.md` — the state × preset × toggle matrix must all render, none crash.
- `reference/animate.md` — pulse dot + config-change crossfade only; state-motion, AOD/Reduce-Motion honored.

## 11. Open questions (defaults asserted)
1. HR zones by HRR reuse spec 013 (iPhone computes, pushes zone). **Asserted.**
2. Weight unit pre-formatted by iPhone (`%@`), not re-derived on watch. **Asserted.**
3. Config sync scope: `WatchScreenConfig` may CloudKit-sync as app config. Re-confirm §I at build. **Asserted.**
