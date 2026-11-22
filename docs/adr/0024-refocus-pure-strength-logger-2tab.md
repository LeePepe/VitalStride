# ADR-0024: Refocus AppUI to a 2-Tab Pure Strength Training Logger

**Status**: Accepted  
**Date**: 2026-11-22  
**Deciders**: project owner

## Context

VitalStride accumulated a 5-tab top-level navigation (`Overview`, `Workout`, `Data`, `AI`, `Settings`) alongside multiple AI-powered surfaces across the workout flow (training advice cards, smart exercise substitute sheets, AI model/API key configuration, and multi-domain physiological dashboards). While the underlying SPM packages (`VitalModels`, `HealthKitService`, `AIService`, `VitalUI`, `TelemetryKit`, `DesignKit`, `FlightKit`) provide solid, well-tested foundations for physiological analytics (HRV corridors, sleep debt, ATL/CTL/TSB, aerobic decoupling) and four-layer AI advice routing, bundling generic health dashboards and AI prompts directly into the primary strength-training logger diluted the core user experience.

The product owner decided to split the long-term product family into focused apps sharing the same local SPM package foundation:
1. **VitalStride (V1 Refocus)**: a pure, fast, zero-distraction strength training logger.
2. **Future Cycling & Endurance App**: reuses `HealthKitService` (EF, Pa:Hr, ATL/CTL/TSB, HR zones) and `VitalModels`.
3. **Future AI Daily Coach App**: reuses `AIService` (`FourLayerAdviceEngine`, `AIRouter`, Bandit routing) and `HealthKitService`.

## Decision

Refocus the VitalStride `AppUI` layer into a **2-Tab Pure Strength Training Logger** (Option B + Phase 1 100% pure tool experience):

1. **2-Tab Primary Navigation (`ContentView` / `AppNavigation`)**:
   - Default selected tab on launch is `.workout` (`AppNavigation.selectedTab = .workout`).
   - `ContentView` renders only two tabs: **训练 (`AppTab.workout` → `WorkoutListView`)** and **设置 (`AppTab.settings` → `SettingsView`)**.
   - Top-level `Overview`, `Data`, and `AI` tabs are removed from `ContentView` (while keeping `AppTab` enum cases and underlying view files intact so non-primary / shared compilation targets remain non-destructive).
2. **Hide All AI Entry Points in Reachable AppUI Flows**:
   - **`WorkoutListView`**: do not render `AITrainingAdviceCard`, do not auto-trigger `adviceViewModel.loadAdviceIfNeeded` on list appearance, and remove the `WorkoutLoadProgressionView` toolbar entry that surfaces AI four-layer periodization prescriptions.
   - **`ActiveWorkoutView` & `ActiveExerciseSection` & `ActiveWorkoutFocusStageView`**: remove the AI "Smart Substitute" (`active_workout.substitute.menu_title` / `onSubstitute` / `ExerciseSubstituteSheet`) menu item from active workout exercise menus while preserving manual exercise replacement (`替换动作` → `ExercisePickerView`). Note: deterministic local progression (`SmartProgressionAdvisor` / `PreviousSetLookup`) is pure math in `AppUI`/`VitalModels` with zero LLM/AI dependency and remains part of the strength logger.
   - **`WorkoutDetailView`**: confirmed free of `AIQuickAnalysisCard` or AI triggers; keep pure workout summary, heart rate zones/HRR, set table, and 1RM trend.
   - **`StartWorkoutView` / `WorkoutTemplateBuilder`**: confirmed free of AI routine generation entry points; keep blank workout, copy from history, and start from template.
   - **`SettingsView`**: remove `AISettingsSection()` from the settings `Form`, leaving HealthKit permissions, unit preferences, Apple Watch workout screen configuration, data import/export, about, and FlightKit debug flags.
3. **Preserve `Packages/**` 100% Intact**:
   - Do not delete or weaken any public API, model, calculator, or test in `Packages/VitalModels`, `Packages/HealthKitService`, `Packages/AIService`, `Packages/VitalUI`, `Packages/TelemetryKit`, `Packages/DesignKit`, or `Packages/FlightKit`.

## Consequences

### Positive

- Launching VitalStride drops the user straight into the `Workout` tab with zero AI latency, API key prompts, or dashboard clutter.
- All strength logging workflows (tiled/focus dual mode, custom numeric keypad, unilateral sets, drop/pyramid subsets, rest timer Live Activity, Apple Watch live heart rate, 1RM Epley trends, and workout calendar) remain front and center.
- `Packages/HealthKitService` and `Packages/AIService` remain 100% intact and green for future sibling apps or gated re-introduction.

### Negative

- Users cannot access the `Overview`, `Data`, or `AI` tabs or configure AI provider keys from the iOS `SettingsView` UI in V1.
- Existing tests that asserted `AppNavigation().selectedTab != .workout` on initial launch must be updated to assert `AppNavigation().selectedTab == .workout`.

## Implementation references

- `VitalStride/Sources/ContentView.swift`
- `VitalStride/Sources/WorkoutListView.swift`
- `VitalStride/Sources/ActiveWorkoutView.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStride/Sources/SettingsView.swift`
- `VitalStrideTests/Sources/CrashRecoveryNavigationTests.swift`
- `specs/028-pure-strength-app-refocus/spec.md`

## Revisit triggers

Reopen this decision when launching a dedicated sibling app from the shared `Packages/` foundation, or if a future ADR introduces an opt-in FlightKit flag for on-device coaching inside the strength logger.
