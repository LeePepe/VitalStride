import DesignKit
import HealthKitService
import SwiftUI

// MARK: - WatchInWorkoutView
//
// Composes the four preset skeletons (`fullInfo` 3·2·1 default,
// `hrFocus` 2·1, `list` 1·1·1·1, `nextFocus` 1·2 inverted) from the
// reusable modules shipped in `WatchWorkoutModules.swift` (MY-1291) and
// the merged display state produced by `WatchWorkoutViewModel` (MY-1290).
//
// Design contract — mirrors `specs/watch-in-workout-screen.md` §4/§5/§7:
//   * One screen, no scroll. Primary action locked bottom in every
//     preset (spec invariant 2).
//   * Two locks: `heartRate` + `primaryAction` always render — the
//     `WatchScreenConfig` initializer already enforces this at the
//     boundary, so the composer trusts `enabledModules`.
//   * Graceful collapse — a disabled module is simply omitted; siblings
//     reflow (band re-justifies, HR right column disappears if both
//     `hrZone` + `hrAvgPeak` are off, etc.).
//   * `@Environment(\.isLuminanceReduced)` AOD: modules handle their own
//     tone-down / static-dot; the composer disables the config-change
//     crossfade when `Reduce Motion` is on.
//   * `WorkoutSavingState.saving` swaps the whole tier stack for the
//     saving overlay (spec §6b).
//
// Privacy §I: this file never emits an `os_log`/`print` — HR values
// flow only through the display state to the modules, which are
// contractually silent on bpm.

struct WatchInWorkoutView: View {
    @ObservedObject var viewModel: WatchWorkoutViewModel

    var body: some View {
        WatchInWorkoutCore(
            display: viewModel.display,
            onCompleteSet: { viewModel.sendCompleteSet() }
        )
    }
}

/// Value-driven inner composer — pure view over `WatchWorkoutDisplayState`.
/// Isolated from the view-model so previews (and future snapshot tests)
/// can render every preset × toggle × state combination without touching
/// the WCSession pipeline.
struct WatchInWorkoutCore: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let display: WatchWorkoutDisplayState
    var onCompleteSet: () -> Void = {}

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(theme.neutrals.bg)
            .foregroundStyle(theme.neutrals.text1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.2),
                value: display.config
            )
    }

    @ViewBuilder
    private var content: some View {
        if display.saving == .saving {
            WatchSavingOverlayModule()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                presetTiers
                Spacer(minLength: 4) // invariant 2: pin action to bottom
                WatchPrimaryActionModule(
                    nextSet: display.nextSet,
                    onCompleteSet: onCompleteSet,
                    onFinish: onCompleteSet,
                    onLogSet: onCompleteSet
                )
            }
        }
    }

    @ViewBuilder
    private var presetTiers: some View {
        switch display.config.preset {
        case .fullInfo:
            fullInfoTiers
        case .hrFocus:
            hrFocusTiers
        case .list:
            listTiers
        case .nextFocus:
            nextFocusTiers
        }
    }

    // MARK: - A. fullInfo (3·2·1) — DEFAULT

    @ViewBuilder
    private var fullInfoTiers: some View {
        sessionBand
        hrHeroRow
        if display.config.enabledModules.contains(.nextSet) {
            WatchNextSetBlockModule(
                nextSet: display.nextSet,
                showDots: display.config.enabledModules.contains(.setDots),
                variant: .regular
            )
        }
    }

    private var hrHeroRow: some View {
        HStack(alignment: .top, spacing: 6) {
            WatchHRHeroModule(hr: display.hr, font: TypeScale.metricXL)
            Spacer(minLength: 0)
            let showZone = display.config.enabledModules.contains(.hrZone)
            let showAvgPeak = display.config.enabledModules.contains(.hrAvgPeak)
            if showZone || showAvgPeak {
                VStack(alignment: .trailing, spacing: 5) {
                    if showZone {
                        WatchHRZonePillModule(hr: display.hr, variant: .long)
                    }
                    if showAvgPeak {
                        WatchHRAvgPeakModule(
                            averageBPM: display.averageBPM,
                            peakBPM: display.peakBPM
                        )
                    }
                }
            }
        }
    }

    // MARK: - B. hrFocus (2·1) — HR centered, XXL

    @ViewBuilder
    private var hrFocusTiers: some View {
        sessionBand
        WatchHRHeroCenteredModule(
            hr: display.hr,
            showZonePill: display.config.enabledModules.contains(.hrZone),
            averageBPM: display.config.enabledModules.contains(.hrAvgPeak) ? display.averageBPM : nil,
            peakBPM: display.config.enabledModules.contains(.hrAvgPeak) ? display.peakBPM : nil
        )
        .padding(.top, 4)
        // `nextSet` is off by default in hrFocus, but the toggle can still
        // enable it. When on, render the regular block after the hero so
        // one screen with no scroll is preserved on 41mm (spec §5).
        if display.config.enabledModules.contains(.nextSet) {
            WatchNextSetBlockModule(
                nextSet: display.nextSet,
                showDots: display.config.enabledModules.contains(.setDots),
                variant: .regular
            )
        }
    }

    // MARK: - C. list (1·1·1·1) — every metric as a labeled row

    @ViewBuilder
    private var listTiers: some View {
        sessionBand
        VStack(spacing: 0) {
            // heartRate is locked-on → row always renders.
            WatchListHRRow(hr: display.hr)
            if display.config.enabledModules.contains(.nextSet) {
                WatchListNextSetRow(nextSet: display.nextSet)
            }
            if display.config.enabledModules.contains(.elapsed) {
                WatchListDurationRow(elapsedSeconds: display.elapsedSeconds)
            }
            if display.config.enabledModules.contains(.hrAvgPeak) {
                WatchListAvgPeakRow(
                    averageBPM: display.averageBPM,
                    peakBPM: display.peakBPM
                )
            }
        }
    }

    // MARK: - D. nextFocus (1·2 inverted) — HR compressed, next-set hero

    @ViewBuilder
    private var nextFocusTiers: some View {
        WatchHRBandChipModule(
            hr: display.hr,
            elapsedSeconds: display.elapsedSeconds,
            showZonePill: display.config.enabledModules.contains(.hrZone),
            showElapsed: display.config.enabledModules.contains(.elapsed)
        )
        // The next-set hero block is the tier-2 hero even when the
        // `nextSet` toggle is off — nextFocus without a next-set slot
        // has no reason to exist as a preset, so we still render the
        // block; when the toggle is off we swap in a compact freeform
        // pill to preserve the invariant "no blank tier" (spec §5).
        if display.config.enabledModules.contains(.nextSet) {
            WatchNextSetBlockModule(
                nextSet: display.nextSet,
                showDots: display.config.enabledModules.contains(.setDots),
                variant: .hero
            )
        } else {
            WatchNextSetBlockModule(
                nextSet: nil,
                showDots: false,
                variant: .regular
            )
        }
    }

    // MARK: - Shared session band (tier 1 for fullInfo / hrFocus / list)

    @ViewBuilder
    private var sessionBand: some View {
        let modules = display.config.enabledModules
        let showClock = modules.contains(.clock)
        let showElapsed = modules.contains(.elapsed)
        let showSets = modules.contains(.setsTotal)
        let count = (showClock ? 1 : 0) + (showElapsed ? 1 : 0) + (showSets ? 1 : 0)
        if count > 0 {
            HStack(spacing: 0) {
                if showClock {
                    WatchClockModule()
                }
                if showElapsed {
                    if showClock { Spacer(minLength: 4) }
                    WatchElapsedModule(elapsedSeconds: display.elapsedSeconds, variant: .band)
                }
                if showSets {
                    if showClock || showElapsed { Spacer(minLength: 4) }
                    WatchSetsBandModule(progress: display.progress)
                }
                if count == 1 { Spacer(minLength: 0) }
            }
        }
    }
}

// MARK: - Preview harness
//
// A value-only seed helper so reviewers can eyeball every preset ×
// toggle × HR-state combination without launching the real WC pipeline.
// The 176×216 canvas approximates the 41mm safe area so the "one
// screen, no scroll" invariant (spec §5, invariant 1) is easy to
// verify at design time.

#if DEBUG
enum WatchInWorkoutViewPreview {
    static let sampleNextSet = WatchNextSetDisplay(
        id: UUID(),
        index: 3,
        total: 5,
        exerciseName: "Squat",
        targetReps: 8,
        targetWeightKg: 60,
        isLastSetOfWorkout: false
    )

    static func makeState(
        preset: WatchScreenConfig.Preset,
        enabled: Set<WatchScreenConfig.Module>? = nil,
        hr: HRDisplayState = .connected(bpm: 128, zone: 3),
        nextSet: WatchNextSetDisplay? = sampleNextSet,
        elapsed: TimeInterval? = 1458,
        setsDone: Int = 6,
        setsTotal: Int = 12,
        avg: Int? = 122,
        peak: Int? = 141,
        saving: WorkoutSavingState = .idle,
        connection: WatchConnectionState = .reachable
    ) -> WatchWorkoutDisplayState {
        let modules = enabled ?? Set(WatchScreenConfig.Module.allCases)
        let config = WatchScreenConfig(
            preset: preset,
            enabledModules: modules,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        return WatchWorkoutDisplayState(
            config: config,
            hr: hr,
            elapsedSeconds: elapsed,
            progress: WatchProgressDisplay(
                completedSetCount: setsDone,
                totalSetCount: setsTotal
            ),
            currentExerciseName: nextSet?.exerciseName,
            nextSet: nextSet,
            averageBPM: avg,
            peakBPM: peak,
            connection: connection,
            saving: saving
        )
    }
}

private struct WatchPreviewCanvas<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        content()
            .frame(width: 176, height: 216) // 41mm-ish safe area
            .previewDisplayName(title)
    }
}

#Preview("A · fullInfo (default)") {
    WatchPreviewCanvas("A · fullInfo") {
        WatchInWorkoutCore(display: WatchInWorkoutViewPreview.makeState(preset: .fullInfo))
            .designThemePreview()
    }
}

#Preview("B · hrFocus") {
    WatchPreviewCanvas("B · hrFocus") {
        WatchInWorkoutCore(
            display: WatchInWorkoutViewPreview.makeState(
                preset: .hrFocus,
                enabled: [.elapsed, .setsTotal, .hrZone, .hrAvgPeak, .heartRate, .primaryAction]
            )
        )
        .designThemePreview()
    }
}

#Preview("C · list") {
    WatchPreviewCanvas("C · list") {
        WatchInWorkoutCore(display: WatchInWorkoutViewPreview.makeState(preset: .list))
            .designThemePreview()
    }
}

#Preview("D · nextFocus") {
    WatchPreviewCanvas("D · nextFocus") {
        WatchInWorkoutCore(
            display: WatchInWorkoutViewPreview.makeState(
                preset: .nextFocus,
                enabled: [.elapsed, .hrZone, .setDots, .nextSet, .heartRate, .primaryAction]
            )
        )
        .designThemePreview()
    }
}

#Preview("HR — not connected · freeform") {
    WatchPreviewCanvas("Not connected · freeform") {
        WatchInWorkoutCore(
            display: WatchInWorkoutViewPreview.makeState(
                preset: .fullInfo,
                hr: .notConnected,
                nextSet: nil,
                elapsed: 0,
                setsDone: 0,
                setsTotal: 0,
                avg: nil,
                peak: nil,
                connection: .unreachable
            )
        )
        .designThemePreview()
    }
}

#Preview("HR — connecting") {
    WatchPreviewCanvas("Connecting") {
        WatchInWorkoutCore(
            display: WatchInWorkoutViewPreview.makeState(
                preset: .fullInfo,
                hr: .connectedNoData,
                avg: nil,
                peak: nil
            )
        )
        .designThemePreview()
    }
}

#Preview("Last set of workout") {
    WatchPreviewCanvas("Last set") {
        WatchInWorkoutCore(
            display: WatchInWorkoutViewPreview.makeState(
                preset: .fullInfo,
                nextSet: WatchNextSetDisplay(
                    id: UUID(),
                    index: 5,
                    total: 5,
                    exerciseName: "Deadlift",
                    targetReps: 5,
                    targetWeightKg: 100,
                    isLastSetOfWorkout: true
                ),
                setsDone: 11,
                setsTotal: 12
            )
        )
        .designThemePreview()
    }
}

#Preview("Session saving") {
    WatchPreviewCanvas("Saving") {
        WatchInWorkoutCore(
            display: WatchInWorkoutViewPreview.makeState(preset: .fullInfo, saving: .saving)
        )
        .designThemePreview()
    }
}

#Preview("fullInfo — minimal toggles (HR + action only)") {
    WatchPreviewCanvas("fullInfo minimal") {
        WatchInWorkoutCore(
            display: WatchInWorkoutViewPreview.makeState(
                preset: .fullInfo,
                enabled: [] // locked-on invariant still forces HR + action
            )
        )
        .designThemePreview()
    }
}

#Preview("list — minimal") {
    WatchPreviewCanvas("list minimal") {
        WatchInWorkoutCore(
            display: WatchInWorkoutViewPreview.makeState(
                preset: .list,
                enabled: [.elapsed, .setsTotal, .clock]
            )
        )
        .designThemePreview()
    }
}
#endif
