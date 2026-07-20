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
        // Only `heartRate` + `primaryAction` are locked. When `.nextSet`
        // is disabled we omit the hero block entirely — the outer
        // `Spacer(minLength: 4)` in `content` handles reflow and keeps
        // the primary action pinned to the bottom (spec §5 invariant 2 +
        // MY-1292 P0-2: "reflow when a non-locked module is off").
        if display.config.enabledModules.contains(.nextSet) {
            WatchNextSetBlockModule(
                nextSet: display.nextSet,
                showDots: display.config.enabledModules.contains(.setDots),
                variant: .hero
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
//
// MY-1292 P0-3 coverage — the matrix previews below iterate every
// non-locked toggle for each preset (all-on, locked-only, and each
// individual toggle flipped off), plus the three HR states and the
// saving overlay, so acceptance criterion "every preset × toggle
// combination at 41mm" is verifiable at design time.

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

    /// Toggleable modules — the seven `Module` cases that are NOT
    /// contract-locked. Iterated by the matrix previews so every
    /// preset × single-toggle-off combination is rendered.
    static let toggleableModules: [WatchScreenConfig.Module] = [
        .clock, .elapsed, .setsTotal, .hrZone, .hrAvgPeak, .nextSet, .setDots
    ]

    /// The two contract-locked modules — always retained by
    /// `WatchScreenConfig.init` regardless of caller intent.
    static let lockedModules: Set<WatchScreenConfig.Module> = [.heartRate, .primaryAction]

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

    /// A named preset × toggle-set combination used by the matrix.
    struct Fixture: Identifiable {
        let id: String
        let preset: WatchScreenConfig.Preset
        let enabled: Set<WatchScreenConfig.Module>
    }

    /// All non-locked toggles enabled — verifies default rendering.
    static func allOnFixtures() -> [Fixture] {
        WatchScreenConfig.Preset.allCases.map { preset in
            Fixture(
                id: "\(preset.rawValue) · all",
                preset: preset,
                enabled: Set(WatchScreenConfig.Module.allCases)
            )
        }
    }

    /// Only the two locked modules enabled — verifies the "collapse to
    /// bare minimum" case respects the locked-on invariant + never
    /// shows a blank tier (spec §5 invariant 2).
    static func lockedOnlyFixtures() -> [Fixture] {
        WatchScreenConfig.Preset.allCases.map { preset in
            Fixture(
                id: "\(preset.rawValue) · locked only",
                preset: preset,
                enabled: lockedModules
            )
        }
    }

    /// For every preset, one fixture per single toggle turned OFF (the
    /// remaining six toggles + locked stay on). This gives the reviewer
    /// coverage of every preset × toggle-off combination required by
    /// acceptance criteria — 4 presets × 7 toggles = 28 fixtures.
    static func singleToggleOffFixtures() -> [Fixture] {
        var out: [Fixture] = []
        for preset in WatchScreenConfig.Preset.allCases {
            for turnedOff in toggleableModules {
                let enabled = Set(WatchScreenConfig.Module.allCases).subtracting([turnedOff])
                out.append(
                    Fixture(
                        id: "\(preset.rawValue) · no \(turnedOff.rawValue)",
                        preset: preset,
                        enabled: enabled
                    )
                )
            }
        }
        return out
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

/// Matrix strip — vertically stacks a scrollable list of 41mm canvases
/// so reviewers can eyeball every preset × toggle fixture in one
/// preview without opening 30 separate #Preview blocks. Individual
/// #Preview blocks below expose the four presets' default renderings
/// for quick single-canvas checks.
private struct WatchMatrixStrip: View {
    let title: String
    let fixtures: [WatchInWorkoutViewPreview.Fixture]
    var hr: HRDisplayState = .connected(bpm: 128, zone: 3)
    var nextSet: WatchNextSetDisplay? = WatchInWorkoutViewPreview.sampleNextSet
    var saving: WorkoutSavingState = .idle
    var connection: WatchConnectionState = .reachable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.caption.bold())
                    .padding(.horizontal, 4)
                ForEach(fixtures) { fixture in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fixture.id)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        WatchInWorkoutCore(
                            display: WatchInWorkoutViewPreview.makeState(
                                preset: fixture.preset,
                                enabled: fixture.enabled,
                                hr: hr,
                                nextSet: nextSet,
                                saving: saving,
                                connection: connection
                            )
                        )
                        .frame(width: 176, height: 216)
                        .border(Color.gray.opacity(0.3), width: 0.5)
                    }
                }
            }
            .padding(8)
        }
    }
}

// MARK: Per-preset single-canvas previews (fast eyeball)

#Preview("A · fullInfo (default)") {
    WatchPreviewCanvas("A · fullInfo") {
        WatchInWorkoutCore(display: WatchInWorkoutViewPreview.makeState(preset: .fullInfo))
            .designThemePreview()
    }
}

#Preview("B · hrFocus (default)") {
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

#Preview("C · list (default)") {
    WatchPreviewCanvas("C · list") {
        WatchInWorkoutCore(display: WatchInWorkoutViewPreview.makeState(preset: .list))
            .designThemePreview()
    }
}

#Preview("D · nextFocus (default)") {
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

// MARK: HR / lifecycle state previews

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

// MARK: Comprehensive matrix previews (MY-1292 P0-3)
// One #Preview per matrix so the reviewer can scroll through every
// preset × toggle combination without editing this file.

#Preview("Matrix — all toggles ON (4 presets)") {
    WatchMatrixStrip(
        title: "All toggles ON",
        fixtures: WatchInWorkoutViewPreview.allOnFixtures()
    )
    .designThemePreview()
}

#Preview("Matrix — locked-only (4 presets, invariant check)") {
    WatchMatrixStrip(
        title: "Locked-only (HR + action)",
        fixtures: WatchInWorkoutViewPreview.lockedOnlyFixtures()
    )
    .designThemePreview()
}

#Preview("Matrix — single toggle OFF (28 fixtures)") {
    WatchMatrixStrip(
        title: "Each toggleable module OFF (per preset)",
        fixtures: WatchInWorkoutViewPreview.singleToggleOffFixtures()
    )
    .designThemePreview()
}

#Preview("Matrix — HR states × 4 presets (not connected)") {
    WatchMatrixStrip(
        title: "HR: not connected",
        fixtures: WatchInWorkoutViewPreview.allOnFixtures(),
        hr: .notConnected,
        nextSet: nil,
        connection: .unreachable
    )
    .designThemePreview()
}

#Preview("Matrix — HR states × 4 presets (connecting)") {
    WatchMatrixStrip(
        title: "HR: connected, no data yet",
        fixtures: WatchInWorkoutViewPreview.allOnFixtures(),
        hr: .connectedNoData
    )
    .designThemePreview()
}

#Preview("Matrix — saving overlay × 4 presets") {
    WatchMatrixStrip(
        title: "Saving overlay",
        fixtures: WatchInWorkoutViewPreview.allOnFixtures(),
        saving: .saving
    )
    .designThemePreview()
}
#endif
