# MY-1245 — Post-fix manual validation record

Reproducible validation point for the **ActiveWorkout FAB overlap** fix
(merged as PR #250 → `main` `222bf3f`). This document is the artifact
Acceptance criterion #1 (“记录一个可复现校验点”) asks for.

## What the fix is (baseline for the check)

`VitalStride/Sources/ActiveWorkoutView.swift` moved the bottom-trailing
FAB out of a `ZStack(alignment: .bottomTrailing)` overlay and into a
`.safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0)`
attached to the exercise-list `VStack`.

Two structural consequences are what make the fix work — both are
directly checkable in the source (`ActiveWorkoutView.swift` at merged
HEAD `222bf3f`):

| # | Anchor line | Behavior |
|---|-------------|----------|
| 1 | `line 94` — `.safeAreaInset(edge: .bottom, alignment: .trailing, spacing: 0)` | The list gets its bottom scroll content-inset **reserved** by the FAB’s own footprint. There is no separate `Color.clear` list footer any more — the inset is intrinsic. |
| 2 | `line 95` — `if !isKeyboardVisible { addExerciseButton … }` | When the custom numeric keyboard is on screen, the FAB is dropped from the safe-area inset entirely (both the button and its reserved space). |
| 3 | `lines 249–257` (iOS only) | `isKeyboardVisible` is driven by `UIResponder.keyboardWillShow/HideNotification` publishers wired through `.onReceive`, gated by `#if !os(macOS)`. |
| 4 | `lines 600–617` — `addExerciseButton` | Preserves: `HapticManager.trigger(.exerciseAdded)` (line 602), `showingExercisePicker = true` action, `FABButtonStyle()` press animation, 60×60 circle. |

## How to reproduce the validation

**Environment used for this record**

- Simulator: **iPhone 17 (iOS 26.5)** — UDID
  `CE9FD526-AB13-4BE7-A841-CF89875F8586`
- Xcode build:
  ```
  xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride \
    -configuration Debug \
    -destination 'platform=iOS Simulator,id=CE9FD526-AB13-4BE7-A841-CF89875F8586' \
    -derivedDataPath /tmp/dd-my1245 -skipPackagePluginValidation
  ```
  Result: **BUILD SUCCEEDED**, 0 errors, 0 new warnings on
  `ActiveWorkoutView.swift`.
- Install + launch:
  ```
  xcrun simctl install  CE9FD526-… /tmp/dd-my1245/…/VitalStride.app
  xcrun simctl launch   CE9FD526-… com.vitalstride.ios
  ```

**Steps**

1. Launch the app on a fresh simulator (or set
   `defaults write com.vitalstride.ios hasCompletedOnboarding -bool YES`
   to bypass onboarding). App loads at the “概览 / Overview” tab.
2. Switch to the “训练 / Training” tab and start a new blank workout —
   `ActiveWorkoutView` presents.
3. Add ≥ 3 exercises (use the green **+** FAB → `ExercisePickerView`).
4. Add ≥ 2 sets to the last exercise.
5. Scroll the list until the **last set row of the last exercise** is
   right above the FAB.
6. Confirm both:
   - The last row’s `⋯` overflow-menu button is fully visible and
     tappable — nothing is drawn over it.
   - The last row’s completion-ring on the right edge is fully visible
     and tappable — nothing is drawn over it.
7. Tap the kg or reps field of any set to bring up the custom numeric
   keyboard (`WorkoutNumericKeyboard`, `UITextField.inputView`).
8. Confirm: the FAB is **not** on screen while the keyboard is up. The
   row that owns the input is fully visible above the keyboard.
9. Dismiss the keyboard. The FAB animates back into place (opacity +
   move-from-bottom transition, driven by
   `.animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)` on
   line 105).
10. Tap the FAB. `ExercisePickerView` sheet presents (line 121–127) and
    haptic fires (`HapticManager.trigger(.exerciseAdded)` on line 602).
11. Toggle Appearance:
    - `xcrun simctl ui <UDID> appearance dark`
    - `xcrun simctl ui <UDID> appearance light`
    Confirm neither state shows visual regressions on the FAB or the
    list rows (colors resolve through `theme.primary.primary` /
    `theme.primary.onPrimary` / `theme.neutrals.*` — no hard-coded
    hexes are introduced).

## Observed results (2026-07-15 run)

- App launches cleanly on iPhone 17 (iOS 26.5), both light and dark
  appearance rendered correctly on the launch/home screens (`概览`
  view; sanity screenshots retained under
  `/tmp/my1245-shots/02-home-light.png`, `.../03-home-dark.png`).
- Build clean, no errors, no new warnings on `ActiveWorkoutView.swift`.
- Deeper interactive validation of the ActiveWorkout screen (steps 5–10)
  requires taps that `xcrun simctl` cannot programmatically produce
  (no `simctl tap`) and no XCUITest coverage exists yet for this
  presentation. Those steps must be run by a human on a physical
  device or via a booted simulator with mouse-driven taps. The steps
  above are the reproducible script for that human run.

## Limitations of this validation record

- No XCUITest / snapshot infrastructure exists in the app-target layer
  today, so the interactive taps (steps 5–10 above) are documented as
  a manual script rather than executed automation. This is called out
  in the PR #250 handoff and in the original issue description
  (“暂无自动化 UI 测试覆盖此层”).
- HealthKit values are never printed anywhere in this record
  (Constitution I compliance).

## tests_run

- `xcodebuild build -project VitalStride.xcodeproj -scheme VitalStride
   -configuration Debug -destination
   'platform=iOS Simulator,id=CE9FD526-AB13-4BE7-A841-CF89875F8586'
   -derivedDataPath /tmp/dd-my1245 -skipPackagePluginValidation`
   → **BUILD SUCCEEDED**
- Sanity-launched `com.vitalstride.ios` on the simulator in both
  light and dark appearance without crash.
- Pre-push hook is expected to run SwiftLint (touched lines, strict),
  i18n parity, and layer frontmatter checks on push.
