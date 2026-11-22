# Implementation Plan: Refocus VitalStride AppUI to a 2-Tab Pure Strength Logger

**Feature Branch**: `feat/vs-pure-strength-app`  
**Layer**: `AppUI` (`VitalStride/Sources/**`, `VitalStrideTests/**`) + Support Documentation (`docs/adr/`, `specs/028-pure-strength-app-refocus/`)  
**Authority**: [ADR-0024](../../docs/adr/0024-refocus-pure-strength-logger-2tab.md), [spec.md](spec.md)

## Summary

1. **TK1 (`EXP-SPEC`)**: Complete R11 audit of 5-Tab navigation and AI UI entry points across `VitalStride/Sources` and `VitalStrideTests`, author `docs/adr/0024-refocus-pure-strength-logger-2tab.md` and `specs/028-pure-strength-app-refocus/spec.md`, and record exact `Deprecated Test Clauses to Remove/Rewrite` in `handoff/vs-pure-strength-app/spec.md`.
2. **TK2 (`IMPL`)**: Update `ContentView.swift`, `WorkoutListView.swift`, `ActiveWorkoutView.swift`, `ActiveWorkout/ActiveExerciseSection.swift`, and `SettingsView.swift` to enforce the 2-Tab (`训练` + `设置`, default `.workout`) pure strength logger experience with zero AI UI entry points, and migrate `CrashRecoveryNavigationTests.swift` + add regression coverage.
3. **TK3 (`REV-DELIVER`)**: Run V1–V5 cross-vendor review and deliver single PR to `main` via `ci-monitor.py`.

## Owned Paths

- `docs/adr/0024-refocus-pure-strength-logger-2tab.md`
- `docs/adr/README.md`
- `specs/028-pure-strength-app-refocus/spec.md`
- `specs/028-pure-strength-app-refocus/plan.md`
- `VitalStride/Sources/ContentView.swift`
- `VitalStride/Sources/WorkoutListView.swift`
- `VitalStride/Sources/ActiveWorkoutView.swift`
- `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift`
- `VitalStride/Sources/SettingsView.swift`
- `VitalStrideTests/Sources/CrashRecoveryNavigationTests.swift`
- `VitalStrideTests/Sources/SettingsViewTests.swift`

## Files NOT to Touch

- `Packages/**` (all 7 local SPM packages must remain 100% untouched)
- `project.yml` / `VitalStride.xcodeproj/**`
