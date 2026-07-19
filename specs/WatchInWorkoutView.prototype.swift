// WatchInWorkoutView.prototype.swift
// ─────────────────────────────────────────────────────────────────────────────
// DESIGN ARTIFACT for MY-1282 — NOT wired into the Watch target.
// Module-slot reference matching specs/watch-in-workout-screen.md §4/§5/§7.
//
// Two orthogonal config axes:
//   Axis A — WatchLayoutPreset: .fullInfo(3·2·1, default) / .hrFocus(2·1) / .list / .nextFocus
//   Axis B — enabledModules: Set<ModuleID>, with heartRate + primaryAction LOCKED on.
// Invariants: one screen no-scroll · button pinned bottom (Spacer) · disabled modules reflow.
//
// The implementer copies this into `VitalStrideWatch Watch App/`, replaces the mock
// `WorkoutGlanceState` + `WatchScreenConfig` with the real WCSession-backed observables
// from MY-1281, and keeps the token styling verbatim.
//
// Requires DesignKit additions (spec §0):
//   TypeScale.metricXL  = Font.system(size: 44, weight: .semibold).monospacedDigit()
//   TypeScale.metricXXL = Font.system(size: 64, weight: .semibold).monospacedDigit()
// Local fallbacks (`heroFont`, `heroFontXL`) stand in until those land.
// ─────────────────────────────────────────────────────────────────────────────

import SwiftUI
import DesignKit

// MARK: - Data (implementer swaps for the real WCSession observables)

enum HRConnection: Equatable {
    case notConnected
    case connectedNoData
    case connected(bpm: Int, zone: Int)          // zone 1...5, computed on iPhone (spec §11.1)
}

struct SetProgress: Equatable {
    let index: Int                                // 1-based, current set
    let total: Int
}

struct NextSet: Equatable {
    let exercise: String
    let progress: SetProgress
    let reps: Int
    let weightFormatted: String                   // iPhone-formatted, e.g. "60kg"
    let isLast: Bool
}

struct WorkoutGlanceState: Equatable {
    var hr: HRConnection
    var nextSet: NextSet?                          // nil = freeform / no plan
    var clock: String                             // time-of-day "14:32"
    var elapsed: String                           // "24:18"
    var avgHR: Int?
    var peakHR: Int?
    var setsDone: Int
    var setsTotal: Int
}

// MARK: - Config (Axis A + Axis B) — pushed from iPhone via MY-1281 WC channel

enum ModuleID: String, CaseIterable {
    case clock, elapsed, setsTotal          // band
    case heartRate                          // LOCKED
    case hrZone, hrAvgPeak                   // HR right column
    case nextSet, setDots                    // next-set block
    case primaryAction                       // LOCKED
}

enum WatchLayoutPreset: String, CaseIterable {
    case fullInfo    // 3·2·1 (default)
    case hrFocus     // 2·1
    case list        // 1·1·1·1
    case nextFocus   // 1·2 inverted
}

struct WatchScreenConfig: Equatable {
    var preset: WatchLayoutPreset
    var enabledModules: Set<ModuleID>

    /// Two modules can never be disabled (spec §5 invariant 4).
    static let locked: Set<ModuleID> = [.heartRate, .primaryAction]

    func isOn(_ m: ModuleID) -> Bool {
        WatchScreenConfig.locked.contains(m) || enabledModules.contains(m)
    }

    /// Default: fullInfo, everything on.
    static let `default` = WatchScreenConfig(
        preset: .fullInfo,
        enabledModules: Set(ModuleID.allCases)
    )
}

// MARK: - The screen (module-composed, preset-driven)

struct WatchInWorkoutView: View {
    @Environment(\.theme) private var theme
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let state: WorkoutGlanceState
    var config: WatchScreenConfig = .default
    var onCompleteSet: () -> Void = {}
    var onFinish: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preset                                  // Axis A dispatch → composed tiers
            Spacer(minLength: 6)                    // invariant 2: pin button to bottom
            primaryAction                           // LOCKED, present in every preset
        }
        .padding(.horizontal, Space.cardPadding)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.neutrals.bg)
        .foregroundStyle(theme.neutrals.text1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: config)  // config-change crossfade
    }

    // MARK: Axis A — preset skeletons

    @ViewBuilder private var preset: some View {
        switch config.preset {
        case .fullInfo:  fullInfoTiers
        case .hrFocus:   hrFocusTiers
        case .list:      listTiers
        case .nextFocus: nextFocusTiers
        }
    }

    // A. fullInfo — 3·2·1
    @ViewBuilder private var fullInfoTiers: some View {
        sessionBand                                 // tier 1
        hrHeroRow                                   // tier 2
        if config.isOn(.nextSet) { nextSetBlock }   // tier 3
    }

    // B. hrFocus — 2·1 (clock off by default; HR centered + XXL)
    @ViewBuilder private var hrFocusTiers: some View {
        sessionBand
        VStack(spacing: 4) {
            hrHeroCentered
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    // C. list — 1·1·1·1
    @ViewBuilder private var listTiers: some View {
        sessionBand
        VStack(spacing: 0) {
            listRow(label: "心率", value: hrListValue, tint: hrListTint)
            if config.isOn(.nextSet), let s = state.nextSet {
                listRow(label: "下一组", value: "\(s.exercise) \(s.reps)×\(s.weightFormatted)")
            }
            listRow(label: "时长", value: state.elapsed)
            if config.isOn(.hrAvgPeak) {
                listRow(label: "均/峰", value: "\(state.avgHR.map(String.init) ?? "—") / \(state.peakHR.map(String.init) ?? "—")")
            }
        }
    }

    // D. nextFocus — 1·2 (HR compressed to band chip; next-set is hero)
    @ViewBuilder private var nextFocusTiers: some View {
        hrBandChip                                  // tier 1: HR as a compact band row
        nextSetBlock(hero: true)                    // tier 2: enlarged
    }

    // MARK: Tier 1 — session band (clock · elapsed · sets)

    @ViewBuilder private var sessionBand: some View {
        let items = bandItems
        if !items.isEmpty {
            HStack {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    if i > 0 { Spacer() }
                    item
                }
                if items.count == 1 { Spacer() }    // single item left-aligns
            }
        }
    }

    private var bandItems: [AnyView] {
        var v: [AnyView] = []
        if config.isOn(.clock), config.preset != .hrFocus || config.enabledModules.contains(.clock) {
            v.append(AnyView(Text(state.clock)
                .font(TypeScale.meta).fontWeight(.semibold)
                .foregroundStyle(theme.neutrals.text1)))     // clock = brightest
        }
        if config.isOn(.elapsed) {
            v.append(AnyView(Label(state.elapsed, systemImage: "timer")
                .font(TypeScale.meta).foregroundStyle(theme.neutrals.text2)
                .labelStyle(.titleAndIcon)))
        }
        if config.isOn(.setsTotal) {
            v.append(AnyView(Label("\(state.setsDone)/\(state.setsTotal)", systemImage: "circle.lefthalf.filled")
                .font(TypeScale.meta.monospacedDigit()).foregroundStyle(theme.neutrals.text2)
                .labelStyle(.titleAndIcon)))
        }
        return v
    }

    // MARK: Tier 2 variants — HR

    // fullInfo hero row: number left, zone+avg/peak right column
    private var hrHeroRow: some View {
        HStack(alignment: .top, spacing: 6) {
            hrNumberBlock(font: heroFont)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                if config.isOn(.hrZone) { zonePill }
                if config.isOn(.hrAvgPeak) { avgPeak }
            }
        }
    }

    // hrFocus: oversized centered
    private var hrHeroCentered: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                pulseDot
                heroNumber(font: heroFontXL)
            }
            HStack(spacing: 8) {
                if config.isOn(.hrZone) { zonePill }
                Text(avgInlineText).font(TypeScale.meta).foregroundStyle(theme.neutrals.text3)
            }
        }
    }

    // nextFocus: HR compressed to a band chip row
    private var hrBandChip: some View {
        HStack {
            HStack(spacing: 5) {
                pulseDot
                heroNumber(font: TypeScale.title)
                if config.isOn(.hrZone), case .connected(_, let z) = state.hr {
                    StatusPill("Z\(z)", tone: zoneTone(z))
                }
            }
            Spacer()
            if config.isOn(.elapsed) {
                Label(state.elapsed, systemImage: "timer")
                    .font(TypeScale.meta).foregroundStyle(theme.neutrals.text2).labelStyle(.titleAndIcon)
            }
        }
    }

    private func hrNumberBlock(font: Font) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                pulseDot
                heroNumber(font: font)
            }
            switch state.hr {
            case .notConnected:
                Text("开始训练以连接心率").font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text3).padding(.leading, 14)
            default:
                Text("BPM").font(TypeScale.meta)
                    .foregroundStyle(theme.neutrals.text3).padding(.leading, 14)
            }
        }
    }

    // MARK: Tier 3 — next-set block (shared by fullInfo tier-3 and nextFocus hero)

    @ViewBuilder private func nextSetBlock(hero: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: hero ? 7 : 4) {
            if let s = state.nextSet {
                HStack {
                    SectionHeader(s.isLast ? "最后一组 💪" : "下一组")
                    Spacer()
                    Text("第 \(s.progress.index) / \(s.progress.total) 组")
                        .font(TypeScale.meta).foregroundStyle(theme.neutrals.text3)
                }
                if hero {
                    Text(s.exercise).font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(nsText1)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(s.reps)").font(.system(size: 24, weight: .bold).monospacedDigit()).foregroundStyle(nsText1)
                        Text("次").font(TypeScale.meta).foregroundStyle(theme.neutrals.text3)
                        Text("×").font(TypeScale.body).foregroundStyle(theme.neutrals.text3).padding(.horizontal, 2)
                        Text(s.weightFormatted).font(.system(size: 24, weight: .bold).monospacedDigit()).foregroundStyle(nsText1)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(s.exercise).font(TypeScale.body).foregroundStyle(nsText1)
                        Spacer()
                        Text("\(s.reps)次 × \(s.weightFormatted)")
                            .font(TypeScale.title).foregroundStyle(nsText1)
                    }
                }
                if config.isOn(.setDots) { setDots(s.progress) }
            } else {
                SectionHeader("自由训练")
                Text("无预定计划").font(TypeScale.body).foregroundStyle(theme.neutrals.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(hero ? Space.cardPadding : 11)
        .background(theme.neutrals.inner, in: RoundedRectangle(cornerRadius: Radius.inner))
        .frame(maxHeight: hero ? .infinity : nil)
    }

    private func setDots(_ p: SetProgress) -> some View {
        HStack(spacing: 5) {
            ForEach(1...max(p.total, 1), id: \.self) { i in
                Circle()
                    .fill(dotFill(i, current: p.index))
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle().stroke(theme.primary.primary.opacity(i == p.index && !dimmed ? 0.25 : 0),
                                        lineWidth: 3)
                    )
            }
        }
    }
    private func dotFill(_ i: Int, current: Int) -> Color {
        if dimmed { return i <= current ? theme.neutrals.text3 : theme.neutrals.border }
        if i < current { return theme.primary.primary }
        if i == current { return theme.primary.primary }
        return theme.neutrals.border
    }

    // MARK: List-preset row

    private func listRow(label: String, value: String, tint: Color? = nil) -> some View {
        HStack {
            Text(label.uppercased()).font(TypeScale.meta)
                .foregroundStyle(theme.neutrals.text3)
            Spacer()
            Text(value).font(TypeScale.title).foregroundStyle(tint ?? nsText1)
        }
        .padding(.vertical, 6)
        .overlay(Rectangle().fill(theme.neutrals.border).frame(height: 1), alignment: .bottom)
    }
    private var hrListValue: String {
        switch state.hr {
        case .connected(let bpm, let z): return "\(bpm) · Zone \(z)"
        case .connectedNoData: return "··· · 连接中"
        case .notConnected: return "未连接"
        }
    }
    private var hrListTint: Color? {
        if case .connected(_, let z) = state.hr { return zoneColor(z) }
        return nil
    }

    // MARK: Shared HR atoms

    @ViewBuilder private func heroNumber(font: Font) -> some View {
        switch state.hr {
        case .connected(let bpm, _):
            Text("\(bpm)").font(font)
                .foregroundStyle(dimmed ? theme.neutrals.text2 : theme.neutrals.text1)
                .contentTransition(.numericText())
        case .connectedNoData:
            Text("···").font(font).foregroundStyle(theme.neutrals.text3)
        case .notConnected:
            Text("--").font(font).foregroundStyle(theme.neutrals.text3).accessibilityHidden(true)
        }
    }

    @ViewBuilder private var zonePill: some View {
        switch state.hr {
        case .connected(_, let z): StatusPill("Zone \(z)", tone: zoneTone(z))
        case .connectedNoData:     StatusPill("连接中", tone: .primary)
        case .notConnected:        StatusPill("未连接", tone: .neutral)
        }
    }

    private var avgPeak: some View {
        Text(avgInlineText).font(TypeScale.meta).foregroundStyle(theme.neutrals.text3)
    }
    private var avgInlineText: String {
        "均 \(state.avgHR.map(String.init) ?? "—") · 峰 \(state.peakHR.map(String.init) ?? "—")"
    }

    private var pulseDot: some View {
        Circle().fill(dotColor).frame(width: 8, height: 8).opacity(dotOpacity)
            .animation((dimmed || reduceMotion) ? nil
                       : .easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulseToggle)
            .onAppear { pulseToggle.toggle() }
    }
    @State private var pulseToggle = false
    private var dotOpacity: Double {
        if dimmed { return 0.6 }
        switch state.hr {
        case .connected:       return pulseToggle ? 1.0 : 0.55
        case .connectedNoData: return pulseToggle ? 1.0 : 0.35
        case .notConnected:    return 0.3
        }
    }
    private var dotColor: Color {
        switch state.hr {
        case .connected(_, let z): return zoneColor(z)
        default: return theme.neutrals.text3
        }
    }

    // zone → tone / color (semantic FIXED, never seed-derived) — spec §6a
    private func zoneTone(_ z: Int) -> PillTone {
        switch z { case 1: return .neutral; case 2: return .primary
                   case 3: return .success; case 4: return .warning; default: return .danger }
    }
    private func zoneColor(_ z: Int) -> Color {
        switch z { case 1: return theme.chart(5); case 2: return theme.primary.primary
                   case 3: return theme.success; case 4: return theme.warning; default: return theme.danger }
    }

    private var nsText1: Color { dimmed ? theme.neutrals.text2 : theme.neutrals.text1 }

    // MARK: Locked primary action

    private var primaryAction: some View {
        Button(action: state.nextSet?.isLast == true ? onFinish : onCompleteSet) {
            HStack(spacing: 6) {
                Text(actionLabel)
                Image(systemName: state.nextSet == nil ? "plus" : "checkmark").font(.system(size: 13, weight: .semibold))
            }
            .font(TypeScale.title)
            .frame(maxWidth: .infinity, minHeight: 44)          // HIG 44pt
        }
        .buttonStyle(.plain)
        .foregroundStyle(dimmed ? theme.neutrals.text2 : theme.primary.onPrimary)
        .background(
            RoundedRectangle(cornerRadius: Radius.inner)
                .fill(dimmed ? Color.clear : theme.primary.primary)
                .overlay(RoundedRectangle(cornerRadius: Radius.inner)
                    .strokeBorder(theme.neutrals.border, lineWidth: dimmed ? 1.5 : 0))
        )
    }
    private var actionLabel: String {
        if state.nextSet == nil { return "记录一组" }
        if state.nextSet?.isLast == true { return "完成训练" }
        return "完成这组"
    }
}

// MARK: - Previews: presets × states

private let sampleWorking = WorkoutGlanceState(
    hr: .connected(bpm: 128, zone: 3),
    nextSet: .init(exercise: "深蹲", progress: .init(index: 3, total: 5), reps: 8,
                   weightFormatted: "60kg", isLast: false),
    clock: "14:32", elapsed: "24:18", avgHR: 122, peakHR: 141, setsDone: 6, setsTotal: 12)

#Preview("A · fullInfo (default)") {
    WatchInWorkoutView(state: sampleWorking, config: .default).designThemePreview()
}
#Preview("B · hrFocus") {
    WatchInWorkoutView(state: sampleWorking,
        config: .init(preset: .hrFocus, enabledModules: [.elapsed, .setsTotal, .hrZone]))
        .designThemePreview()
}
#Preview("C · list") {
    WatchInWorkoutView(state: sampleWorking,
        config: .init(preset: .list, enabledModules: Set(ModuleID.allCases)))
        .designThemePreview()
}
#Preview("D · nextFocus") {
    WatchInWorkoutView(state: sampleWorking,
        config: .init(preset: .nextFocus, enabledModules: [.elapsed, .hrZone, .setDots, .nextSet]))
        .designThemePreview()
}
#Preview("Not connected · freeform") {
    WatchInWorkoutView(state: .init(hr: .notConnected, nextSet: nil,
        clock: "09:05", elapsed: "00:00", avgHR: nil, peakHR: nil, setsDone: 0, setsTotal: 0),
        config: .default).designThemePreview()
}
