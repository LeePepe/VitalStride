# Feature Specification: Refocus VitalStride AppUI to a 2-Tab Pure Strength Logger

**Feature Branch**: `feat/vs-pure-strength-app`  
**Created**: 2026-11-22  
**Status**: Approved  
**Authority**: Owner Mandate (`TIA-867` / `vs-pure-strength-app`) & [ADR-0024](../../docs/adr/0024-refocus-pure-strength-logger-2tab.md)

## Intent & Constitution Alignment

Refocus the VitalStride iOS `AppUI` experience into a fast, zero-distraction **Pure Strength Training Logger** with **2 primary tabs (`训练 Workout` + `设置 Settings`)**, defaulting to `.workout` on launch, and hiding all AI UI entry points across reachable screens while preserving all seven local SPM packages (`Packages/**`) intact.

- **Constitution §I (Health Data Privacy)**: Unchanged; no health values are logged or synced to CloudKit.
- **Constitution §II (Swift 6 Strict Concurrency)**: Unchanged; all view/state changes remain `@MainActor`-safe and strict-concurrency compliant.
- **Constitution §III (SPM Package First)**: `Packages/VitalModels`, `Packages/HealthKitService`, `Packages/AIService`, `Packages/VitalUI`, `Packages/TelemetryKit`, `Packages/DesignKit`, and `Packages/FlightKit` remain 100% untouched. All changes are scoped to `VitalStride/Sources/**` and `VitalStrideTests/**` (`AppUI` layer) plus ADR/Spec documentation.
- **Constitution §IV (XcodeGen Source of Truth)**: No target structure changes required; `VitalStrideTests` uses directory source references.
- **Constitution §VI (I18n)**: No raw hardcoded user-visible strings introduced.

## R11 Codebase Exploration & Entry Point Audit (`file:line`)

### 1. Primary 5-Tab Navigation (`VitalStride/Sources/ContentView.swift`)
- `VitalStride/Sources/ContentView.swift:9-12`: `enum AppTab: Hashable { case overview, workout, data, ai, settings }` (retained as enum cases for backward compatibility with `TelemetryHelpers` and dormant views).
- `VitalStride/Sources/ContentView.swift:15-16`: `final class AppNavigation { var selectedTab = AppTab.overview ... }` → must default to `AppTab.workout`.
- `VitalStride/Sources/ContentView.swift:28-55`: `TabView(selection: $nav.selectedTab)` currently renders 5 `Tab` items (`.overview`, `.workout`, `.data`, `.ai`, `.settings`) → must render only `.workout` (`WorkoutListView()`) and `.settings` (`SettingsView()`), backed by `ContentView.visibleTabs == [.workout, .settings]`.

### 2. AI Entry Points Across Reachable Workout & Settings Flows
- **`VitalStride/Sources/WorkoutListView.swift`**:
  - `WorkoutListView.swift:59-60`: `@AppStorage(aiPrivacyConsentKey) private var privacyConsented = false` and `@State private var adviceViewModel = TrainingAdviceViewModel()`.
  - `WorkoutListView.swift:89-99`: `if shouldShowAdviceCard` section rendering `AITrainingAdviceCard(...)`.
  - `WorkoutListView.swift:167-172`: `.task` block calling `adviceViewModel.loadAdviceIfNeeded(modelContext: modelContext)`.
  - `WorkoutListView.swift:187`: `let shouldShowAdviceCard = !unifiedWorkouts.isEmpty && privacyConsented` → must be `false` (or removed from `WorkoutListView` active rendering) so `AITrainingAdviceCard` is never displayed or auto-triggered.
  - `WorkoutListView.swift:287-294`: `ToolbarItem(placement: .secondaryAction)` linking to `WorkoutLoadProgressionView()` (which invokes `FourLayerAdviceEngine` and displays AI provider pills / L3-L4 prescriptions) → hidden from `WorkoutListView` toolbar so the workout tab remains a pure strength history + calendar + quick-start surface.
- **`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift` & `VitalStride/Sources/ActiveWorkoutView.swift`**:
  - `ActiveExerciseSection.swift:329-331`: `Button(action: onSubstitute)` rendering `Label(String(localized: "active_workout.substitute.menu_title", defaultValue: "Smart Substitute", ...), systemImage: "sparkles")` inside `exerciseActionMenu` → hidden so only manual `替换动作` (`onReplace` → `ExercisePickerView`) and `删除动作` (`onDelete`) appear in the exercise menu.
  - `ActiveWorkoutView.swift:141-151, 256, 279`: `ExerciseSubstituteSheet` sheet presentation and `onSubstitute` callbacks hidden/deactivated so active workouts never trigger `SubstitutePromptBuilder` / `AIRouter`.
- **`VitalStride/Sources/WorkoutDetailView.swift`**:
  - Audited `WorkoutDetailView.swift:1-475`: already a pure strength & heart-rate summary view (`概要`, HR zones/HRR, per-exercise set table, `OneRepMaxTrendView`, save as template, delete). Contains no `AIQuickAnalysisCard` or AI entry points.
- **`VitalStride/Sources/StartWorkoutView.swift` & `VitalStride/Sources/WorkoutTemplateBuilder.swift`**:
  - Audited `StartWorkoutView.swift:1-311` and `WorkoutTemplateBuilder.swift:1-54`: only offers `.blank`, `.fromWorkout`, and `.fromTemplate`. Contains no AI routine generation entry points.
- **`VitalStride/Sources/SettingsView.swift`**:
  - `SettingsView.swift:23`: `AISettingsSection()` inside `Form` → removed from `SettingsView` `Form` so API key / AI provider configuration is hidden from user-facing settings.

## Obsolete Test Manifest & Deprecated Test Clauses

Per the **Spec-First Requirement Change Rule**, existing test suites were audited for assertions that conflict with the 2-Tab (`.workout` default) and AI-hidden AppUI contract:

| File & Line | Existing Assertion / Behavior | Disposition |
|---|---|---|
| `VitalStrideTests/Sources/CrashRecoveryNavigationTests.swift:28` | `#expect(navigation.selectedTab != .workout)` assumes `AppNavigation().selectedTab` starts on `.overview` before crash recovery resume sets `.workout`. | **Rewrite**: Assert `#expect(navigation.selectedTab == .workout)` on a newly initialized `AppNavigation()`, and verify that when `navigation.selectedTab` is switched to `.settings` prior to resume, `handleResume()` switches `navigation.selectedTab` back to `.workout`. |
| `VitalStrideTests/Sources/WorkoutListRenderingTests.swift:1-360` | Renders `WorkoutListView` across `.populated`, `.empty`, `.loading`, `.error` states. | **Keep + Extend**: Existing tests pass; add unit test assertions verifying `AppNavigation().selectedTab == .workout`, `ContentView.visibleTabs == [.workout, .settings]`, and that `WorkoutListView` / `SettingsView` / `ActiveExerciseSection` hide AI UI entry points. |
| `VitalStrideTests/Sources/AISettingsSectionTests.swift` & `AITrainingAdviceCardTests.swift` & `AIAnalysisServiceTests.swift` | Unit-test underlying `AIModelSettingsStore`, `buildTrainingContext`, and `AIAnalysisService` directly without mounting them in `ContentView`. | **Keep**: Underlying symbols remain compiled in the target for future reuse; unit tests continue to pass without modification. |

## Functional Requirements

- **FR-028-001 (Default Workout Tab)**: `AppNavigation().selectedTab` MUST initialize to `AppTab.workout`.
- **FR-028-002 (2-Tab Primary Navigation)**: `ContentView.visibleTabs` MUST be `[.workout, .settings]` and `ContentView` MUST render only the `训练` (`WorkoutListView`) and `设置` (`SettingsView`) tabs.
- **FR-028-003 (WorkoutListView Pure Logger)**: `WorkoutListView` MUST NOT render `AITrainingAdviceCard`, MUST NOT trigger `adviceViewModel.loadAdviceIfNeeded` on appearance, and MUST NOT display the `WorkoutLoadProgressionView` AI periodization toolbar link.
- **FR-028-004 (ActiveWorkout Pure Manual Replacement)**: `ActiveExerciseSection` MUST NOT display the AI `Smart Substitute` (`sparkles`) menu item in `exerciseActionMenu`, while preserving manual exercise replacement (`替换动作` → `ExercisePickerView`).
- **FR-028-005 (SettingsView Pure Tool Settings)**: `SettingsView` MUST NOT display `AISettingsSection()` in its `Form`, while preserving `HealthKitPermissionSection`, `UnitPreferencesSection`, `trainingSection` (Apple Watch in-workout screen), `DataImportExportSection`, `aboutSection`, and `flightSection`.
- **FR-028-006 (Package Preservation)**: `Packages/**` MUST have zero file modifications or deletions.

## Verification Strategy

1. Verify `git diff --name-only origin/main -- Packages/` is empty.
2. Run `bash scripts/test-repoinfra.sh`.
3. Run `xcodebuild test -project VitalStride.xcodeproj -scheme VitalStride -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation -only-testing:VitalStrideTests/CrashRecoveryNavigationTests -only-testing:VitalStrideTests/SettingsViewTests -only-testing:VitalStrideTests/WorkoutLoggingV2Tests -only-testing:VitalStrideTests/TelemetryHelpersTests`.
