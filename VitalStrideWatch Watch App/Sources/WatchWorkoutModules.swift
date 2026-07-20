import DesignKit
import HealthKitService
import SwiftUI

// MARK: - WatchWorkoutModules
//
// Reusable, preset-agnostic display modules for the watch in-workout
// screen (spec §5–§9). MY-1291 delivers the module vocabulary; MY-1292
// composes them into the four presets (`fullInfo` / `hrFocus` / `list` /
// `nextFocus`) and wires the real WCSession-backed `WatchWorkoutViewModel`
// (MY-1290) in.
//
// Design contract
// ---------------
// * Every module accepts pure value inputs — no view-model handle, no
//   closure to a service. Callers pass either a slice of
//   `WatchWorkoutDisplayState` or the individual fields the module needs.
// * Modules are preset-agnostic. The compose layer decides which modules
//   render in which tier for which preset. Modules never inspect the
//   preset directly.
// * Token-only styling. Colors from `Theme` (never raw hex); fonts from
//   `TypeScale` (never `.system(size:)` per view — HR heroes use
//   `TypeScale.metricXL` / `metricXXL` from MY-1287). Radius from
//   `Radius.inner`, padding from `Space.cardPadding` where applicable.
// * Numbers are tabular (`.monospacedDigit()` fonts already are).
// * Every user-facing string routes through `String(localized:)` against
//   the `watch.*` xcstrings keys shipped in this same commit (spec §8).
//   No hardcoded Chinese anywhere.
// * Accessibility: each numeric module carries an accessibility label +
//   value pair; the primary action exposes a 44pt hit target per HIG.
// * Privacy §I: HR values are display-only. This file never emits an
//   `os_log` / `print` / telemetry call carrying a bpm. Callers must not
//   log the display state either.

// MARK: - Formatters (shared, deterministic)

enum WatchWorkoutFormatters {
    /// "24:18" (< 1h `mm:ss`) or "01:24:18" (≥ 1h `HH:MM:SS`). Spec §8
    /// duration range: 3–4h max, `HH:MM` for hero copy but the runtime
    /// element (which ticks per-second) uses `mm:ss` / `HH:MM:SS` for
    /// legibility. Nil → "00:00".
    static func formatElapsed(_ seconds: TimeInterval?) -> String {
        let total = max(0, Int(seconds ?? 0))
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// "6/12". Nil-progress collapses to "0/0" so callers can hide the
    /// module upstream (bandItems drop it entirely when disabled).
    static func formatSetsBand(_ progress: WatchProgressDisplay?) -> String {
        let done = progress?.completedSetCount ?? 0
        let total = progress?.totalSetCount ?? 0
        return String(
            format: String(localized: "watch.band.sets", defaultValue: "%lld/%lld"),
            done,
            total
        )
    }

    /// 24h clock "HH:MM". Uses `DateFormatter` (not `Date.formatted`) so
    /// spec §8 24h invariant is honored regardless of user 12/24h locale.
    static func formatClock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// "60kg" / "—". iPhone would normally pre-format (§11.2) but until
    /// that lands the watch shows `kg` with 0/1 decimal places.
    static func formatWeight(_ kg: Double?) -> String {
        guard let kg else { return "—" }
        if kg == kg.rounded() {
            return "\(Int(kg))kg"
        }
        return String(format: "%.1fkg", kg)
    }

    /// "8次 × 60kg" — reps + weight combined form used by fullInfo
    /// tier-3 next-set right column.
    static func formatSetTarget(reps: Int?, weightKg: Double?) -> String {
        let repsCount = reps ?? 0
        let weight = formatWeight(weightKg)
        return String(
            format: String(localized: "watch.set.format", defaultValue: "%lld reps × %@"),
            repsCount,
            weight
        )
    }
}

// MARK: - Localized helpers

private enum WatchModuleStrings {
    static var hrNotConnected: String {
        String(localized: "watch.hr.notConnected", defaultValue: "Not connected")
    }
    static var hrConnecting: String {
        String(localized: "watch.hr.connecting", defaultValue: "Connecting")
    }
    static var hrHintStart: String {
        String(localized: "watch.hr.hint.start", defaultValue: "Start a workout to connect HR")
    }
    static var nextSetLabel: String {
        String(localized: "watch.nextSet.label", defaultValue: "Next set")
    }
    static var nextSetFreeform: String {
        String(localized: "watch.nextSet.freeform", defaultValue: "Freeform")
    }
    static var nextSetNoPlan: String {
        String(localized: "watch.nextSet.noplan", defaultValue: "No planned session")
    }
    static var nextSetLast: String {
        String(localized: "watch.nextSet.last", defaultValue: "Last set 💪")
    }
    static var listHR: String {
        String(localized: "watch.list.hr", defaultValue: "HR")
    }
    static var listNextSet: String {
        String(localized: "watch.list.nextSet", defaultValue: "Next")
    }
    static var listDuration: String {
        String(localized: "watch.list.duration", defaultValue: "Duration")
    }
    static var listAvgPeak: String {
        String(localized: "watch.list.avgPeak", defaultValue: "Avg / Peak")
    }
    static var actionCompleteSet: String {
        String(localized: "watch.action.completeSet", defaultValue: "Complete set")
    }
    static var actionLogSet: String {
        String(localized: "watch.action.logSet", defaultValue: "Log set")
    }
    static var actionFinish: String {
        String(localized: "watch.action.finish", defaultValue: "Finish workout")
    }
    static var saving: String {
        String(localized: "watch.saving", defaultValue: "Saving workout…")
    }
    static var bpmUnit: String {
        // "BPM" is unit — same in all locales.
        "BPM"
    }

    static func hrZoneLong(_ z: Int) -> String {
        String(
            format: String(localized: "watch.hr.zone", defaultValue: "Zone %lld"),
            z
        )
    }
    static func hrZoneShort(_ z: Int) -> String {
        String(
            format: String(localized: "watch.hr.zoneShort", defaultValue: "Z%lld"),
            z
        )
    }
    static func hrAvgPeak(avg: Int, peak: Int) -> String {
        String(
            format: String(localized: "watch.hr.avgPeak", defaultValue: "avg %lld · peak %lld"),
            avg,
            peak
        )
    }
    static func nextSetProgress(index: Int, total: Int) -> String {
        String(
            format: String(localized: "watch.nextSet.progress", defaultValue: "Set %lld of %lld"),
            index,
            total
        )
    }
}

// MARK: - Zone → color/tone

/// Maps an HR zone (1…5) to the DesignKit pill tone spec §6a assigns.
/// Kept a free function so composition-side call sites can render the
/// same tone in whatever container they need.
func watchZoneTone(_ zone: Int) -> PillTone {
    switch zone {
    case 1: return .neutral
    case 2: return .primary
    case 3: return .success
    case 4: return .warning
    default: return .danger
    }
}

/// Maps an HR zone to the accent color used for the pulse dot / list-row
/// tint. Reads directly from `theme` (semantic tokens, never raw hex).
func watchZoneColor(_ zone: Int, theme: Theme) -> Color {
    switch zone {
    case 1: return theme.chart(5)
    case 2: return theme.primary.primary
    case 3: return theme.success
    case 4: return theme.warning
    default: return theme.danger
    }
}

// MARK: - Band modules (clock · elapsed · sets)

/// 24h clock "HH:MM" that live-updates every 30s (once per minute would
/// drift up to a minute; 30s keeps the visible tick within ±30s of the
/// wall clock). Uses `TimelineView(.periodic(...))` so the update happens
/// off the model, cheap, and honors AOD (SwiftUI throttles automatically).
public struct WatchClockModule: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let text = WatchWorkoutFormatters.formatClock(context.date)
            Text(text)
                .font(TypeScale.meta)
                .fontWeight(.semibold)
                .foregroundStyle(theme.neutrals.text1) // brightest of band
                .monospacedDigit()
                .accessibilityLabel(text)
        }
    }
}

/// Elapsed training time. Live-updates every second (session runtime is
/// short-lived so per-second is fine here). Nil ⇒ "00:00" placeholder.
public struct WatchElapsedModule: View {
    @Environment(\.theme) private var theme
    let elapsedSeconds: TimeInterval?
    let variant: Variant

    public enum Variant { case band, hero }

    public init(elapsedSeconds: TimeInterval?, variant: Variant = .band) {
        self.elapsedSeconds = elapsedSeconds
        self.variant = variant
    }

    public var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let ticked = tickedSeconds(now: context.date)
            let text = WatchWorkoutFormatters.formatElapsed(ticked)
            switch variant {
            case .band:
                Label(text, systemImage: "timer")
                    .font(TypeScale.meta.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text2)
                    .labelStyle(.titleAndIcon)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(WatchModuleStrings.listDuration)
                    .accessibilityValue(text)
            case .hero:
                Text(text)
                    .font(TypeScale.metricXL)
                    .foregroundStyle(theme.neutrals.text1)
                    .accessibilityLabel(WatchModuleStrings.listDuration)
                    .accessibilityValue(text)
            }
        }
    }

    /// The elapsed value we render at `now`. Because the timeline ticks
    /// every second, we advance the base value by the offset from when
    /// the snapshot was materialized. Nil-safe: nil ⇒ 0.
    private func tickedSeconds(now: Date) -> TimeInterval {
        // We don't have an anchor Date here (display state carries
        // elapsedSeconds, not startedAt). Composition layer refreshes the
        // display state at least once per WC event; the TimelineView just
        // interpolates between refreshes. So we render the base value
        // and let the next state push move the visible integer.
        return elapsedSeconds ?? 0
    }
}

/// Total-sets progress badge in the session band. Renders "6/12" with
/// the half-filled circle icon. Nil progress renders "0/0".
public struct WatchSetsBandModule: View {
    @Environment(\.theme) private var theme
    let progress: WatchProgressDisplay?

    public init(progress: WatchProgressDisplay?) {
        self.progress = progress
    }

    public var body: some View {
        let text = WatchWorkoutFormatters.formatSetsBand(progress)
        Label(text, systemImage: "circle.lefthalf.filled")
            .font(TypeScale.meta.monospacedDigit())
            .foregroundStyle(theme.neutrals.text2)
            .labelStyle(.titleAndIcon)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "watch.a11y.setsProgress", defaultValue: "Sets progress"))
            .accessibilityValue(text)
    }
}

// MARK: - Heart-rate modules

/// Pulse dot — a small (8pt) colored circle. Pulses 0.35↔1.0 at 1s when
/// state is `connectedNoData`, 0.55↔1.0 when `connected(_)`, and stays
/// dim (0.3 or 0.6 under AOD) when `notConnected`.
public struct WatchHRPulseDotModule: View {
    @Environment(\.theme) private var theme
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toggle = false
    let hr: HRDisplayState
    let size: CGFloat

    public init(hr: HRDisplayState, size: CGFloat = 8) {
        self.hr = hr
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: size, height: size)
            .opacity(opacityValue)
            .animation(
                (dimmed || reduceMotion) ? nil
                    : .easeInOut(duration: 1).repeatForever(autoreverses: true),
                value: toggle
            )
            .onAppear { toggle.toggle() }
            .accessibilityHidden(true)
    }

    private var dotColor: Color {
        if case .connected(_, let zone) = hr, let z = zone {
            return watchZoneColor(z, theme: theme)
        }
        return theme.neutrals.text3
    }

    private var opacityValue: Double {
        if dimmed { return 0.6 }
        switch hr {
        case .connected: return toggle ? 1.0 : 0.55
        case .connectedNoData: return toggle ? 1.0 : 0.35
        case .notConnected: return 0.3
        }
    }
}

/// HR number rendered in whichever font the caller passes. Handles all
/// three states (spec §6a): live bpm, `···` placeholder while connecting,
/// `--` (a11y-hidden) when not connected.
public struct WatchHRNumberModule: View {
    @Environment(\.theme) private var theme
    @Environment(\.isLuminanceReduced) private var dimmed
    let hr: HRDisplayState
    let font: Font

    public init(hr: HRDisplayState, font: Font = TypeScale.metricXL) {
        self.hr = hr
        self.font = font
    }

    public var body: some View {
        switch hr {
        case .connected(let bpm, _):
            Text("\(bpm)")
                .font(font)
                .foregroundStyle(dimmed ? theme.neutrals.text2 : theme.neutrals.text1)
                .contentTransition(.numericText())
                .accessibilityLabel(WatchModuleStrings.listHR)
                .accessibilityValue("\(bpm) \(WatchModuleStrings.bpmUnit)")
        case .connectedNoData:
            Text("···")
                .font(font)
                .foregroundStyle(theme.neutrals.text3)
                .accessibilityLabel(WatchModuleStrings.listHR)
                .accessibilityValue(WatchModuleStrings.hrConnecting)
        case .notConnected:
            Text("--")
                .font(font)
                .foregroundStyle(theme.neutrals.text3)
                .accessibilityLabel(WatchModuleStrings.listHR)
                .accessibilityValue(WatchModuleStrings.hrNotConnected)
        }
    }
}

/// The HR zone pill (spec §6a). Long form ("Zone 3") for the primary
/// column, short form ("Z3") for the compressed band chip.
public struct WatchHRZonePillModule: View {
    let hr: HRDisplayState
    let variant: Variant

    public enum Variant { case long, short }

    public init(hr: HRDisplayState, variant: Variant = .long) {
        self.hr = hr
        self.variant = variant
    }

    public var body: some View {
        switch hr {
        case .connected(_, let zone):
            if let z = zone {
                let text = variant == .long
                    ? WatchModuleStrings.hrZoneLong(z)
                    : WatchModuleStrings.hrZoneShort(z)
                StatusPill(text, tone: watchZoneTone(z))
                    .accessibilityLabel(WatchModuleStrings.hrZoneLong(z))
            } else {
                EmptyView() // spec §6a: hide pill when zone is unknown
            }
        case .connectedNoData:
            StatusPill(WatchModuleStrings.hrConnecting, tone: .primary)
                .accessibilityLabel(WatchModuleStrings.hrConnecting)
        case .notConnected:
            StatusPill(WatchModuleStrings.hrNotConnected, tone: .neutral)
                .accessibilityLabel(WatchModuleStrings.hrNotConnected)
        }
    }
}

/// Avg/peak inline line. "均 122 · 峰 141" with em-dash placeholders when
/// a value is nil.
public struct WatchHRAvgPeakModule: View {
    @Environment(\.theme) private var theme
    let averageBPM: Int?
    let peakBPM: Int?

    public init(averageBPM: Int?, peakBPM: Int?) {
        self.averageBPM = averageBPM
        self.peakBPM = peakBPM
    }

    public var body: some View {
        let text = displayText
        Text(text)
            .font(TypeScale.meta)
            .foregroundStyle(theme.neutrals.text3)
            .monospacedDigit()
            .accessibilityLabel(WatchModuleStrings.listAvgPeak)
            .accessibilityValue(text)
    }

    private var displayText: String {
        if let avg = averageBPM, let peak = peakBPM {
            return WatchModuleStrings.hrAvgPeak(avg: avg, peak: peak)
        }
        // Show the format shell even before samples arrive so the shape
        // is legible; use em-dash for missing values. Route through the
        // catalog so zh/en render the correct connective ("均"/"avg").
        let avg = averageBPM.map { String($0) } ?? "—"
        let peak = peakBPM.map { String($0) } ?? "—"
        // Reuse the format shell with placeholder ints as sentinels: fall
        // back to a locale-neutral compact form here to avoid hardcoded CJK.
        return String(
            format: String(localized: "watch.hr.avgPeakPlaceholder", defaultValue: "avg %@ · peak %@"),
            avg,
            peak
        )
    }
}

/// Full HR hero row (fullInfo tier 2): pulse dot + number left, "BPM" or
/// "开始训练以连接心率" sub-label below the number. Optional right column
/// (zone pill + avg/peak) rendered by the caller alongside.
public struct WatchHRHeroModule: View {
    @Environment(\.theme) private var theme
    let hr: HRDisplayState
    let font: Font

    public init(hr: HRDisplayState, font: Font = TypeScale.metricXL) {
        self.hr = hr
        self.font = font
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                WatchHRPulseDotModule(hr: hr)
                WatchHRNumberModule(hr: hr, font: font)
            }
            subLabel
                .font(TypeScale.meta)
                .foregroundStyle(theme.neutrals.text3)
                .padding(.leading, 14)
        }
    }

    @ViewBuilder private var subLabel: some View {
        switch hr {
        case .notConnected:
            Text(WatchModuleStrings.hrHintStart)
        default:
            Text(WatchModuleStrings.bpmUnit)
        }
    }
}

/// Centered oversized HR hero for the `hrFocus` preset (2·1): pulse dot
/// + XXL number centered, zone pill + avg-inline row beneath.
public struct WatchHRHeroCenteredModule: View {
    @Environment(\.theme) private var theme
    let hr: HRDisplayState
    let showZonePill: Bool
    let averageBPM: Int?
    let peakBPM: Int?

    public init(
        hr: HRDisplayState,
        showZonePill: Bool = true,
        averageBPM: Int? = nil,
        peakBPM: Int? = nil
    ) {
        self.hr = hr
        self.showZonePill = showZonePill
        self.averageBPM = averageBPM
        self.peakBPM = peakBPM
    }

    public var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WatchHRPulseDotModule(hr: hr)
                WatchHRNumberModule(hr: hr, font: TypeScale.metricXXL)
            }
            HStack(spacing: 8) {
                if showZonePill {
                    WatchHRZonePillModule(hr: hr, variant: .long)
                }
                WatchHRAvgPeakModule(averageBPM: averageBPM, peakBPM: peakBPM)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Compact band-row HR chip for the `nextFocus` preset (1·2 inverted).
/// Pulse dot + smaller number + short-zone chip on the left, optional
/// elapsed timer on the right.
public struct WatchHRBandChipModule: View {
    @Environment(\.theme) private var theme
    let hr: HRDisplayState
    let elapsedSeconds: TimeInterval?
    let showZonePill: Bool
    let showElapsed: Bool

    public init(
        hr: HRDisplayState,
        elapsedSeconds: TimeInterval? = nil,
        showZonePill: Bool = true,
        showElapsed: Bool = true
    ) {
        self.hr = hr
        self.elapsedSeconds = elapsedSeconds
        self.showZonePill = showZonePill
        self.showElapsed = showElapsed
    }

    public var body: some View {
        HStack {
            HStack(spacing: 5) {
                WatchHRPulseDotModule(hr: hr)
                WatchHRNumberModule(hr: hr, font: TypeScale.title.monospacedDigit())
                if showZonePill, case .connected(_, let zone) = hr, let z = zone {
                    StatusPill(WatchModuleStrings.hrZoneShort(z), tone: watchZoneTone(z))
                        .accessibilityLabel(WatchModuleStrings.hrZoneLong(z))
                }
            }
            Spacer()
            if showElapsed {
                WatchElapsedModule(elapsedSeconds: elapsedSeconds, variant: .band)
            }
        }
    }
}

// MARK: - Next-set modules

/// Set-progress dot array (spec §5 next-set block). Renders `total`
/// small circles; positions `< index` are filled with primary (done),
/// `== index` is filled with primary + subtle halo (current), the rest
/// are the border tone (todo).
public struct WatchSetDotsModule: View {
    @Environment(\.theme) private var theme
    @Environment(\.isLuminanceReduced) private var dimmed
    let currentIndex: Int
    let total: Int

    public init(currentIndex: Int, total: Int) {
        self.currentIndex = currentIndex
        self.total = total
    }

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(total, 1), id: \.self) { i in
                Circle()
                    .fill(fill(for: i))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(
                                theme.primary.primary.opacity(i == currentIndex && !dimmed ? 0.25 : 0),
                                lineWidth: 3
                            )
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "watch.a11y.setDots", defaultValue: "Set dots"))
        .accessibilityValue(
            WatchModuleStrings.nextSetProgress(index: currentIndex, total: max(total, 1))
        )
    }

    private func fill(for i: Int) -> Color {
        if dimmed {
            return i <= currentIndex ? theme.neutrals.text3 : theme.neutrals.border
        }
        if i <= currentIndex {
            return theme.primary.primary
        }
        return theme.neutrals.border
    }
}

/// Next-set block. Two rendering variants:
///   - `.regular` (fullInfo tier 3): exercise + reps×weight side-by-side,
///     dots below.
///   - `.hero` (nextFocus tier 2 hero): exercise name bigger, reps × weight
///     each in its own oversized numeric block, dots below.
///
/// A nil `nextSet` swaps in the freeform "自由训练 / 无预定计划" state.
public struct WatchNextSetBlockModule: View {
    @Environment(\.theme) private var theme
    @Environment(\.isLuminanceReduced) private var dimmed
    let nextSet: WatchNextSetDisplay?
    let showDots: Bool
    let variant: Variant

    public enum Variant { case regular, hero }

    public init(
        nextSet: WatchNextSetDisplay?,
        showDots: Bool = true,
        variant: Variant = .regular
    ) {
        self.nextSet = nextSet
        self.showDots = showDots
        self.variant = variant
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: variant == .hero ? 7 : 4) {
            if let s = nextSet {
                header(for: s)
                if variant == .hero {
                    heroBody(for: s)
                } else {
                    regularBody(for: s)
                }
                if showDots {
                    WatchSetDotsModule(currentIndex: s.index, total: s.total)
                }
            } else {
                SectionHeader(WatchModuleStrings.nextSetFreeform)
                Text(WatchModuleStrings.nextSetNoPlan)
                    .font(TypeScale.body)
                    .foregroundStyle(theme.neutrals.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(variant == .hero ? Space.cardPadding : 11)
        .background(
            theme.neutrals.inner,
            in: RoundedRectangle(cornerRadius: Radius.inner)
        )
        .frame(maxHeight: variant == .hero ? .infinity : nil)
        .accessibilityElement(children: .contain)
    }

    private func header(for s: WatchNextSetDisplay) -> some View {
        HStack {
            SectionHeader(s.isLastSetOfWorkout ? WatchModuleStrings.nextSetLast : WatchModuleStrings.nextSetLabel)
            Spacer()
            Text(WatchModuleStrings.nextSetProgress(index: s.index, total: s.total))
                .font(TypeScale.meta)
                .foregroundStyle(theme.neutrals.text3)
                .monospacedDigit()
        }
    }

    private func heroBody(for s: WatchNextSetDisplay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.exerciseName)
                .font(TypeScale.title)
                .foregroundStyle(nsText1)
                .accessibilityLabel(s.exerciseName)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(s.targetReps ?? 0)")
                    .font(TypeScale.metricXL.monospacedDigit())
                    .foregroundStyle(nsText1)
                Text(String(localized: "watch.set.reps.unit", defaultValue: "reps"))
                    .font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text3)
                Text("×")
                    .font(TypeScale.body)
                    .foregroundStyle(theme.neutrals.text3)
                    .padding(.horizontal, 2)
                Text(WatchWorkoutFormatters.formatWeight(s.targetWeightKg))
                    .font(TypeScale.metricXL.monospacedDigit())
                    .foregroundStyle(nsText1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WatchModuleStrings.nextSetLabel)
            .accessibilityValue(
                WatchWorkoutFormatters.formatSetTarget(reps: s.targetReps, weightKg: s.targetWeightKg)
            )
        }
    }

    private func regularBody(for s: WatchNextSetDisplay) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(s.exerciseName)
                .font(TypeScale.body)
                .foregroundStyle(nsText1)
            Spacer()
            Text(
                WatchWorkoutFormatters.formatSetTarget(reps: s.targetReps, weightKg: s.targetWeightKg)
            )
            .font(TypeScale.title.monospacedDigit())
            .foregroundStyle(nsText1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(WatchModuleStrings.nextSetLabel) \(s.exerciseName)")
        .accessibilityValue(
            WatchWorkoutFormatters.formatSetTarget(reps: s.targetReps, weightKg: s.targetWeightKg)
        )
    }

    private var nsText1: Color {
        dimmed ? theme.neutrals.text2 : theme.neutrals.text1
    }
}

// MARK: - List preset rows

/// Shared list-row visual (label uppercase left, value right, bottom
/// hairline). Used by the four `WatchListXxxRow` modules; kept private
/// so composers pick from the typed row set rather than assembling ad-hoc.
private struct WatchListRow: View {
    @Environment(\.theme) private var theme
    let label: String
    let value: String
    let tint: Color?

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(TypeScale.meta)
                .foregroundStyle(theme.neutrals.text3)
            Spacer()
            Text(value)
                .font(TypeScale.title.monospacedDigit())
                .foregroundStyle(tint ?? theme.neutrals.text1)
        }
        .padding(.vertical, 6)
        .overlay(
            Rectangle()
                .fill(theme.neutrals.border)
                .frame(height: 1),
            alignment: .bottom
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

public struct WatchListHRRow: View {
    @Environment(\.theme) private var theme
    let hr: HRDisplayState

    public init(hr: HRDisplayState) {
        self.hr = hr
    }

    public var body: some View {
        WatchListRow(label: WatchModuleStrings.listHR, value: valueText, tint: tint)
    }

    private var valueText: String {
        switch hr {
        case .connected(let bpm, let zone):
            if let z = zone {
                return "\(bpm) · \(WatchModuleStrings.hrZoneLong(z))"
            }
            return "\(bpm)"
        case .connectedNoData:
            return "··· · \(WatchModuleStrings.hrConnecting)"
        case .notConnected:
            return WatchModuleStrings.hrNotConnected
        }
    }

    private var tint: Color? {
        if case .connected(_, let zone) = hr, let z = zone {
            return watchZoneColor(z, theme: theme)
        }
        return nil
    }
}

public struct WatchListNextSetRow: View {
    let nextSet: WatchNextSetDisplay?

    public init(nextSet: WatchNextSetDisplay?) {
        self.nextSet = nextSet
    }

    public var body: some View {
        WatchListRow(label: WatchModuleStrings.listNextSet, value: valueText, tint: nil)
    }

    private var valueText: String {
        guard let s = nextSet else {
            return WatchModuleStrings.nextSetFreeform
        }
        let target = WatchWorkoutFormatters.formatSetTarget(reps: s.targetReps, weightKg: s.targetWeightKg)
        return "\(s.exerciseName) \(target)"
    }
}

public struct WatchListDurationRow: View {
    let elapsedSeconds: TimeInterval?

    public init(elapsedSeconds: TimeInterval?) {
        self.elapsedSeconds = elapsedSeconds
    }

    public var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            WatchListRow(
                label: WatchModuleStrings.listDuration,
                value: WatchWorkoutFormatters.formatElapsed(elapsedSeconds),
                tint: nil
            )
        }
    }
}

public struct WatchListAvgPeakRow: View {
    let averageBPM: Int?
    let peakBPM: Int?

    public init(averageBPM: Int?, peakBPM: Int?) {
        self.averageBPM = averageBPM
        self.peakBPM = peakBPM
    }

    public var body: some View {
        let avg = averageBPM.map { String($0) } ?? "—"
        let peak = peakBPM.map { String($0) } ?? "—"
        return WatchListRow(
            label: WatchModuleStrings.listAvgPeak,
            value: "\(avg) / \(peak)",
            tint: nil
        )
    }
}

// MARK: - Primary action

/// Locked-bottom primary action. Copy switches by state (spec §6b):
///   - no next set (freeform) → "记录一组"
///   - last set of workout → "完成训练"
///   - otherwise → "完成这组"
///
/// 44pt minimum height per HIG. Under AOD (`isLuminanceReduced`) the
/// filled background is replaced with a border outline so the seed color
/// doesn't burn pixels.
public struct WatchPrimaryActionModule: View {
    @Environment(\.theme) private var theme
    @Environment(\.isLuminanceReduced) private var dimmed
    let nextSet: WatchNextSetDisplay?
    let onCompleteSet: () -> Void
    let onFinish: () -> Void
    let onLogSet: () -> Void

    public init(
        nextSet: WatchNextSetDisplay?,
        onCompleteSet: @escaping () -> Void = {},
        onFinish: @escaping () -> Void = {},
        onLogSet: @escaping () -> Void = {}
    ) {
        self.nextSet = nextSet
        self.onCompleteSet = onCompleteSet
        self.onFinish = onFinish
        self.onLogSet = onLogSet
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
            }
            .font(TypeScale.title)
            .frame(maxWidth: .infinity, minHeight: 44) // HIG 44pt
        }
        .buttonStyle(.plain)
        .foregroundStyle(dimmed ? theme.neutrals.text2 : theme.primary.onPrimary)
        .background(
            RoundedRectangle(cornerRadius: Radius.inner)
                .fill(dimmed ? Color.clear : theme.primary.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.inner)
                        .strokeBorder(theme.neutrals.border, lineWidth: dimmed ? 1.5 : 0)
                )
        )
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
    }

    private var label: String {
        if nextSet == nil { return WatchModuleStrings.actionLogSet }
        if nextSet?.isLastSetOfWorkout == true { return WatchModuleStrings.actionFinish }
        return WatchModuleStrings.actionCompleteSet
    }

    private var iconName: String {
        nextSet == nil ? "plus" : "checkmark"
    }

    private func action() {
        if nextSet == nil {
            onLogSet()
        } else if nextSet?.isLastSetOfWorkout == true {
            onFinish()
        } else {
            onCompleteSet()
        }
    }
}

// MARK: - Saving overlay

/// Full-screen "保存训练…" overlay for `WorkoutSavingState.saving`
/// (spec §6b). Composers render this above the tier stack when
/// `state.saving != .idle`.
public struct WatchSavingOverlayModule: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(theme.primary.primary)
            Text(WatchModuleStrings.saving)
                .font(TypeScale.meta)
                .foregroundStyle(theme.neutrals.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.neutrals.bg)
        .accessibilityLabel(WatchModuleStrings.saving)
    }
}

// MARK: - Previews (sanity for module authors; MY-1292 composes them)

#Preview("HR hero — connected zone 3") {
    WatchHRHeroModule(hr: .connected(bpm: 128, zone: 3))
        .designThemePreview()
}

#Preview("HR hero — connecting") {
    WatchHRHeroModule(hr: .connectedNoData)
        .designThemePreview()
}

#Preview("HR hero — not connected") {
    WatchHRHeroModule(hr: .notConnected)
        .designThemePreview()
}

#Preview("HR hero centered — XXL") {
    WatchHRHeroCenteredModule(
        hr: .connected(bpm: 128, zone: 3),
        averageBPM: 122,
        peakBPM: 141
    )
    .designThemePreview()
}

#Preview("HR band chip") {
    WatchHRBandChipModule(hr: .connected(bpm: 128, zone: 3), elapsedSeconds: 1458)
        .designThemePreview()
}

#Preview("Next-set — regular") {
    WatchNextSetBlockModule(
        nextSet: WatchNextSetDisplay(
            id: UUID(),
            index: 3,
            total: 5,
            exerciseName: "Squat",
            targetReps: 8,
            targetWeightKg: 60,
            isLastSetOfWorkout: false
        )
    )
    .designThemePreview()
}

#Preview("Next-set — hero") {
    WatchNextSetBlockModule(
        nextSet: WatchNextSetDisplay(
            id: UUID(),
            index: 3,
            total: 5,
            exerciseName: "Squat",
            targetReps: 8,
            targetWeightKg: 60,
            isLastSetOfWorkout: false
        ),
        variant: .hero
    )
    .designThemePreview()
}

#Preview("Next-set — freeform") {
    WatchNextSetBlockModule(nextSet: nil)
        .designThemePreview()
}

#Preview("List HR row") {
    VStack(spacing: 0) {
        WatchListHRRow(hr: .connected(bpm: 128, zone: 3))
        WatchListNextSetRow(nextSet: WatchNextSetDisplay(
            id: UUID(), index: 3, total: 5, exerciseName: "Squat",
            targetReps: 8, targetWeightKg: 60, isLastSetOfWorkout: false
        ))
        WatchListDurationRow(elapsedSeconds: 1458)
        WatchListAvgPeakRow(averageBPM: 122, peakBPM: 141)
    }
    .padding()
    .designThemePreview()
}

#Preview("Primary action — complete set") {
    WatchPrimaryActionModule(nextSet: WatchNextSetDisplay(
        id: UUID(), index: 3, total: 5, exerciseName: "Squat",
        targetReps: 8, targetWeightKg: 60, isLastSetOfWorkout: false
    ))
    .padding()
    .designThemePreview()
}

#Preview("Primary action — freeform (log)") {
    WatchPrimaryActionModule(nextSet: nil)
        .padding()
        .designThemePreview()
}

#Preview("Primary action — finish") {
    WatchPrimaryActionModule(nextSet: WatchNextSetDisplay(
        id: UUID(), index: 5, total: 5, exerciseName: "Squat",
        targetReps: 8, targetWeightKg: 60, isLastSetOfWorkout: true
    ))
    .padding()
    .designThemePreview()
}

#Preview("Band composed") {
    HStack {
        WatchClockModule()
        Spacer()
        WatchElapsedModule(elapsedSeconds: 1458)
        Spacer()
        WatchSetsBandModule(progress: WatchProgressDisplay(completedSetCount: 6, totalSetCount: 12))
    }
    .padding()
    .designThemePreview()
}
