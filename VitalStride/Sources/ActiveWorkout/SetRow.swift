// swiftlint:disable no_hardcoded_chinese
// Set Row (Always Editable).
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). Pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065). MY-1073 wires each weight
// / reps input to the shared custom `WorkoutNumericKeyboard` and consolidates
// the previous Menu function items (pyramid / drop-set / unilateral toggle)
// into the keyboard's left column.

import SwiftData
import SwiftUI
import VitalModels
import VitalUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

/// MY-1013: shared 44pt hit-target size for compact SetRow / SubSetRow
/// controls. Kept as a single source of truth so the SetRow completion
/// button, SetRow ellipsis Menu trigger, and SubSetRow completion button
/// cannot drift below Constitution P1-H (>=44pt tappable + accessibility
/// target) independently. Held here (SetRow.swift) rather than in a new
/// file so the fix stays inside the two files authorized for MY-1013.
enum ActiveWorkoutHitTarget {
    /// Rendered hit-region side length (pt). Constitution P1-H requires
    /// >= 44pt on iOS; VoiceOver rotor also uses rendered geometry.
    static let side: CGFloat = 44
}

struct SetRow: View {
    let index: Int
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let canDelete: Bool
    /// Optional exercise context for the keyboard's preset resolver.
    let exercise: Exercise?
    /// Most recent same-exercise weight (kg) for the preset fallback chain.
    let recentWeightKg: Double?
    /// MY-1161 (spec 004-previous-set-hint T005 / FR-001, FR-003, FR-004) —
    /// same-index main set from the most recent prior completed workout for
    /// this exercise, or `nil` when unavailable. When non-nil the row renders
    /// a tertiary caption "上次 {weight}{unit} × {reps}" under the inputs.
    /// Weight comes in as canonical kg from `PreviousSetLookup`; the row
    /// formats it against the current `weightUnit` preference. Defaults to
    /// `nil` so existing call sites (ActiveExerciseSection, previews) remain
    /// source-compatible until T006 wires the lookup through.
    let previousSet: ExerciseSet?
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void
    let onDelete: () -> Void
    let onAddSubSet: (_ type: SetType) -> Void
    /// MY-1073 — invoked when the keyboard's Copy key fires. The parent
    /// section covers/appends the next set as documented in the issue.
    let onCopyToNext: () -> Void

    init(
        index: Int,
        exerciseSet: ExerciseSet,
        weightUnit: WeightUnit,
        canDelete: Bool,
        exercise: Exercise?,
        recentWeightKg: Double?,
        previousSet: ExerciseSet? = nil,
        onToggleCompleted: @escaping (_ wasCompleted: Bool) -> Void,
        onDelete: @escaping () -> Void,
        onAddSubSet: @escaping (_ type: SetType) -> Void,
        onCopyToNext: @escaping () -> Void
    ) {
        self.index = index
        self.exerciseSet = exerciseSet
        self.weightUnit = weightUnit
        self.canDelete = canDelete
        self.exercise = exercise
        self.recentWeightKg = recentWeightKg
        self.previousSet = previousSet
        self.onToggleCompleted = onToggleCompleted
        self.onDelete = onDelete
        self.onAddSubSet = onAddSubSet
        self.onCopyToNext = onCopyToNext
    }

    @State private var weightText: String = ""
    @State private var weightRightText: String = ""
    @State private var repsText: String = ""
    // MY-1091: row-level Large Mode is driven off the same persisted flag the
    // toolbar toggle writes in MY-1088. @AppStorage observes the key so the
    // row re-renders when the toolbar toggles without any explicit
    // environment plumbing from ActiveWorkoutView.
    @AppStorage("activeWorkoutLargeMode") private var largeMode = false
    // MY-1202 (spec 006-smart-progression T005): the advisor consumes the
    // caller-collected `[ExerciseSet]` main-set sequence from the user's most
    // recent session for the current exercise. History collection walks
    // `PreviousSetLookup.previousMainSet(...)` (spec 004) by `mainSetIndex`
    // until it returns nil, so the row needs a SwiftData context. Env-driven
    // to keep the caller signature (ActiveExerciseSection) untouched — T005
    // scope forbids editing that file.
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        // MY-1091 P0 fix: wrap Large Mode's row in `ViewThatFits(in: .horizontal)`
        // so the wide 110/88/88 tokens render on Pro Max / landscape and the
        // compact 88/64/68 tokens render on iPhone SE / Mini (375pt content
        // width after 16pt list insets = 343pt). Normal mode has always fit
        // compact widths, so it skips the ViewThatFits wrapper entirely.
        //
        // MY-1161 (spec 004 T005): when `previousSet` is non-nil, render a
        // tertiary "上次 …" caption directly under the row inputs. When nil,
        // nothing is rendered and no vertical space is reserved (FR-003).
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if largeMode {
                    ViewThatFits(in: .horizontal) {
                        rowContent(variant: .large)
                        rowContent(variant: .largeCompact)
                    }
                } else {
                    rowContent(variant: .normal)
                }
            }
            if let previousSet {
                previousSetCaption(previousSet)
            }
            if let advice = smartProgressionAdvice() {
                smartProgressionChip(advice)
            }
        }
        .onAppear {
            let displayW = weightUnit == .lb ? exerciseSet.weight * 2.20462 : exerciseSet.weight
            weightText = formatWeight(displayW)
            if let rightWeight = exerciseSet.weightRight {
                let displayWR = weightUnit == .lb ? rightWeight * 2.20462 : rightWeight
                weightRightText = formatWeight(displayWR)
            }
            repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
        }
    }

    /// Row layout parameterized by a Large Mode `Variant`. `ViewThatFits`
    /// picks between `.large` and `.largeCompact` based on the offered
    /// horizontal space, so the trailing menu / completion button never
    /// clip off-screen on compact phones.
    @ViewBuilder
    private func rowContent(variant: LargeWorkoutFieldWidth.Variant) -> some View {
        // Map the Large Mode variant back to the `large: Bool` axis used by
        // font/min-height tokens — both `.large` and `.largeCompact` still
        // want the larger fonts and 60pt min-height; only widths shrink.
        let isLarge = variant != .normal
        HStack(spacing: LargeWorkoutFieldWidth.rowSpacing(variant)) {
            Text("\(index + 1)")
                .font(LargeWorkoutFonts.setIndex(large: isLarge))
                .foregroundStyle(.secondary)
                .frame(width: LargeWorkoutFieldWidth.setIndexWidth(variant), alignment: .leading)

            if exerciseSet.isUnilateral {
                // MY-876: unilateral order matches bilateral "weight × reps":
                // left-weight / right-weight × reps. Reps stays at the tail so
                // the visual/accessibility sequence is consistent across modes.
                weightField(
                    binding: $weightText,
                    field: .weight,
                    width: LargeWorkoutFieldWidth.unilateralWeight(variant),
                    a11yLabel: String(
                        localized: "第 \(index + 1) 组左侧重量",
                        comment: "Left weight input a11y label"
                    ),
                    a11yHint: String(localized: "输入左侧重量数值", comment: "Left weight input a11y hint")
                )

                Text("/")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                weightField(
                    binding: $weightRightText,
                    field: .weightRight,
                    width: LargeWorkoutFieldWidth.unilateralWeight(variant),
                    a11yLabel: String(
                        localized: "第 \(index + 1) 组右侧重量",
                        comment: "Right weight input a11y label"
                    ),
                    a11yHint: String(localized: "输入右侧重量数值", comment: "Right weight input a11y hint")
                )

                Text("×")
                    .foregroundStyle(.secondary)

                repsField(width: LargeWorkoutFieldWidth.reps(variant))
            } else {
                weightField(
                    binding: $weightText,
                    field: .weight,
                    width: LargeWorkoutFieldWidth.bilateralWeight(variant),
                    a11yLabel: String(
                        localized: "第 \(index + 1) 组重量",
                        comment: "Total weight input a11y label"
                    ),
                    a11yHint: String(localized: "输入重量数值", comment: "Total weight input a11y hint")
                )

                Text("×")
                    .foregroundStyle(.secondary)

                repsField(width: LargeWorkoutFieldWidth.reps(variant))
            }

            Menu {
                if canDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(
                            String(localized: "删除", comment: "Delete set menu item"),
                            systemImage: "trash"
                        )
                    }
                }

                Divider()

                Picker(selection: Binding(
                    get: { exerciseSet.setType },
                    set: { exerciseSet.setType = $0 }
                )) {
                    ForEach(SetType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                } label: {
                    Text(String(localized: "组类型", comment: "Set type picker label in menu"))
                }

                // MY-1154 (T006/T007): RPE picker — hidden for warmup sets
                // (per spec Edge Case, warmup is typically RPE < 6). Options
                // expose the standard 6–10 range plus a "not set" that maps
                // to `nil`. String keys are semantic (English) and their
                // catalog entries land in T008; the value tag stays `Int?`
                // so the picker binding round-trips through
                // `ExerciseSet.rpe` without a sentinel.
                if exerciseSet.setType != .warmup {
                    Picker(selection: Binding(
                        get: { exerciseSet.rpe },
                        set: { exerciseSet.rpe = $0 }
                    )) {
                        Text(String(
                            localized: "set_row_rpe_not_set",
                            defaultValue: "Not set",
                            comment: "RPE picker option: no RPE recorded (maps to nil)"
                        ))
                        .tag(Int?.none)
                        ForEach([6, 7, 8, 9, 10], id: \.self) { value in
                            Text(verbatim: "\(value)").tag(Int?.some(value))
                        }
                    } label: {
                        Text(String(
                            localized: "set_row_rpe_label",
                            defaultValue: "RPE",
                            comment: "RPE (Rate of Perceived Exertion) picker label in set menu"
                        ))
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .frame(width: ActiveWorkoutHitTarget.side, height: ActiveWorkoutHitTarget.side)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "第 \(index + 1) 组设置", comment: "Set configuration menu a11y label"))
            .accessibilityValue(
                exerciseSet.isUnilateral
                    // swiftlint:disable:next line_length
                    ? "\(exerciseSet.setType.displayName)，\(String(localized: "单侧重量", comment: "Unilateral weight a11y value"))"
                    // swiftlint:disable:next line_length
                    : "\(exerciseSet.setType.displayName)，\(String(localized: "总重量", comment: "Total weight a11y value"))"
            )

            Spacer()

            completionButton
        }
    }

    // MARK: - Field builders (routes through the custom keyboard on iOS)

    /// MY-1091: Large Mode weight/reps input font. Text-style-driven so it
    /// stacks with Dynamic Type (see LargeWorkoutMode.swift). Falls back to
    /// `.body` — the SelectAllTextField default — outside Large Mode so the
    /// row keeps its pre-MY-1091 visual density.
    #if canImport(UIKit) && !os(macOS)
    private var inputUIFont: UIFont {
        LargeWorkoutInputFont.weightReps(large: largeMode)
    }
    #endif

    @ViewBuilder
    private func weightField(
        binding: Binding<String>,
        field: SetField,
        width: CGFloat,
        a11yLabel: String,
        a11yHint: String
    ) -> some View {
        #if canImport(UIKit) && !os(macOS)
        SelectAllTextField(
            placeholder: weightUnit.rawValue,
            text: binding,
            keyboardType: .decimalPad,
            font: inputUIFont,
            useCustomKeyboard: true,
            field: field,
            exercise: exercise,
            setType: exerciseSet.setType,
            recentWeightKg: recentWeightKg,
            onLeftAction: { action in handleLeftAction(action, field: field) },
            onPresetReps: { weightKg, reps in handlePresetReps(weightKg: weightKg, reps: reps) }
        )
        .frame(width: width)
        .frame(minHeight: largeMode ? LargeWorkoutFieldWidth.largeMinHeight : nil)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(a11yHint)
        .onChange(of: binding.wrappedValue) { _, newValue in
            let filtered = filterDecimalInput(newValue)
            if filtered != newValue { binding.wrappedValue = filtered }
            if field == .weight {
                syncWeightToModel()
            } else {
                syncWeightRightToModel()
            }
        }
        #else
        SelectAllTextField(
            placeholder: weightUnit.rawValue,
            text: binding,
            keyboardType: .decimalPad
        )
        .frame(width: width)
        .frame(minHeight: largeMode ? LargeWorkoutFieldWidth.largeMinHeight : nil)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(a11yHint)
        .onChange(of: binding.wrappedValue) { _, newValue in
            let filtered = filterDecimalInput(newValue)
            if filtered != newValue { binding.wrappedValue = filtered }
            if field == .weight {
                syncWeightToModel()
            } else {
                syncWeightRightToModel()
            }
        }
        #endif
    }

    @ViewBuilder
    private func repsField(width: CGFloat) -> some View {
        #if canImport(UIKit) && !os(macOS)
        SelectAllTextField(
            placeholder: "次数",
            text: $repsText,
            keyboardType: .numberPad,
            font: inputUIFont,
            useCustomKeyboard: true,
            field: .reps,
            exercise: exercise,
            setType: exerciseSet.setType,
            recentWeightKg: recentWeightKg,
            onLeftAction: { action in handleLeftAction(action, field: .reps) },
            onPresetReps: { weightKg, reps in handlePresetReps(weightKg: weightKg, reps: reps) }
        )
        .frame(width: width)
        .frame(minHeight: largeMode ? LargeWorkoutFieldWidth.largeMinHeight : nil)
        .accessibilityLabel("第 \(index + 1) 组次数")
        .accessibilityHint("输入次数")
        .onChange(of: repsText) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            if filtered != newValue { repsText = filtered }
            syncRepsToModel()
        }
        #else
        SelectAllTextField(
            placeholder: "次数",
            text: $repsText,
            keyboardType: .numberPad
        )
        .frame(width: width)
        .frame(minHeight: largeMode ? LargeWorkoutFieldWidth.largeMinHeight : nil)
        .accessibilityLabel("第 \(index + 1) 组次数")
        .accessibilityHint("输入次数")
        .onChange(of: repsText) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            if filtered != newValue { repsText = filtered }
            syncRepsToModel()
        }
        #endif
    }

    private var completionButton: some View {
        Button {
            let wasCompleted = exerciseSet.isCompleted
            exerciseSet.isCompleted = !wasCompleted
            if !wasCompleted {
                HapticManager.trigger(.setCompleted)
            }
            onToggleCompleted(wasCompleted)
        } label: {
            Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(exerciseSet.isCompleted ? .green : .secondary)
        }
        .buttonStyle(.borderless)
        // MY-1013: unambiguous 44pt hit target (Constitution P1-H). The prior
        // negative vertical padding shrank the layout claim below 44pt so the
        // rendered button bled into the neighboring row — hit-testing on that
        // overhang was ambiguous under compact List row layout. Compact
        // density is preserved by List-level insets and defaultMinListRowHeight
        // in ActiveWorkoutView / ActiveExerciseSection, not by clipping this
        // button's layout claim.
        .frame(width: ActiveWorkoutHitTarget.side, height: ActiveWorkoutHitTarget.side)
        .contentShape(Rectangle())
        .accessibilityLabel("第 \(index + 1) 组，\(exerciseSet.isCompleted ? "已完成" : "未完成")")
        .accessibilityHint("双击切换完成状态")
    }

    // MARK: - Previous-set caption (MY-1161 / spec 004-previous-set-hint T005)

    /// Renders the tertiary "上次 {重量}{单位} × {次数}" caption below the row
    /// inputs when a prior main set is available for this exercise + index
    /// (FR-001). Weight is converted from canonical kg to the user's current
    /// `WeightUnit` preference (FR-004). Unilateral prior sets show both
    /// sides as "L/R" while keeping reps at the tail (spec edge case).
    ///
    /// The format string is `active_workout.previous_set_hint_format`, added
    /// to `Localizable.xcstrings` by T007 (FR-006). Per the T007 catalog
    /// contract, the format takes two positional arguments — `%1$@` for the
    /// formatted weight+unit segment and `%2$lld` for the reps count — so
    /// translations can reorder them without the caller pre-joining them
    /// into a single string.
    @ViewBuilder
    private func previousSetCaption(_ previous: ExerciseSet) -> some View {
        Text(
            String(
                format: String(
                    localized: "active_workout.previous_set_hint_format",
                    defaultValue: "上次 %1$@ × %2$lld",
                    comment: "SetRow previous-set hint. %1$@ is the formatted weight+unit (e.g. \"60kg\" or \"60/58kg\"), %2$lld is the reps count."
                ),
                previousSetWeightSegment(previous),
                Int64(previous.reps)
            )
        )
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    /// Builds the "{weight}{unit}" (or "{L}/{R}{unit}" unilateral) weight
    /// segment for the caption. Weight values are converted from canonical
    /// kg storage to the current `weightUnit` (FR-004). Reps are supplied
    /// separately to the localized format string.
    private func previousSetWeightSegment(_ previous: ExerciseSet) -> String {
        let unitSuffix = weightUnit.rawValue
        if previous.isUnilateral, let rightKg = previous.weightRight {
            let leftDisplay = weightUnit == .lb ? previous.weight * 2.20462 : previous.weight
            let rightDisplay = weightUnit == .lb ? rightKg * 2.20462 : rightKg
            return "\(formatCaptionWeight(leftDisplay))/\(formatCaptionWeight(rightDisplay))\(unitSuffix)"
        }
        let display = weightUnit == .lb ? previous.weight * 2.20462 : previous.weight
        return "\(formatCaptionWeight(display))\(unitSuffix)"
    }

    /// Caption-side weight formatter. Mirrors `formatWeight(_:)` for the
    /// editable input (integer-valued weights strip the decimal, others show
    /// one fraction digit) but keeps a leading "0" when the value is exactly
    /// zero so a legitimately-logged 0kg warmup still reads as "0" in the
    /// caption rather than the empty-input placeholder used by the input.
    private func formatCaptionWeight(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    // MARK: - Smart progression chip (MY-1202 / spec 006-smart-progression T005)

    /// Default target rep range used to drive `SmartProgressionAdvisor` while
    /// no user-facing preference is plumbed. `8...12` is the classic
    /// hypertrophy window and matches the spec's illustrative example
    /// ("上次 12/12/12/12 全达标 → 建议加重"). Plumbing a real user preference
    /// is out of T005 scope; a future task can inject it via an @AppStorage
    /// key without touching the advisor contract.
    private static let defaultRepRange: ClosedRange<Int> = 8...12

    /// Collects the same-exercise main-set sequence from the user's most
    /// recent completed workout by walking 004's `PreviousSetLookup` by
    /// `mainSetIndex` (0, 1, 2, …) until it returns nil, then hands the
    /// sequence to `SmartProgressionAdvisor.suggest(...)`.
    ///
    /// Returns nil when the workout link is missing, the current row lacks a
    /// bound exercise, or the collected sequence is empty (first workout /
    /// no history) — matching the FR-004 edge case that the chip must not
    /// render in that situation. Sub-sets (drop-set / pyramid) are already
    /// filtered out by `PreviousSetLookup.previousMainSet`, so the collected
    /// sequence is main-set only by construction.
    private func smartProgressionAdvice() -> ProgressionAdvice? {
        guard let workout = exerciseSet.workoutExercise?.workout else { return nil }
        guard let boundExercise = exercise else { return nil }

        var previousMainSets: [ExerciseSet] = []
        var mainSetIndex = 0
        while let priorSet = PreviousSetLookup.previousMainSet(
            currentWorkout: workout,
            exercise: boundExercise,
            mainSetIndex: mainSetIndex,
            in: modelContext
        ) {
            previousMainSets.append(priorSet)
            mainSetIndex += 1
        }

        guard !previousMainSets.isEmpty else { return nil }

        return SmartProgressionAdvisor.suggest(
            previousMainSets: previousMainSets,
            userPreferredRepRange: Self.defaultRepRange,
            muscleGroup: boundExercise.muscleGroup
        )
    }

    /// Renders the compact "建议 {重量}{单位} × {次数}" chip plus the advice
    /// reason directly under the row inputs (and, when present, the
    /// spec-004 "上次 …" caption).
    ///
    /// Tap-to-fill wiring lives in T006; telemetry lives in T008 — both are
    /// deliberately out of scope for T005 per the assignment authorization
    /// boundary. The chip is a read-only visual affordance here.
    ///
    /// The chip is styled as a rounded capsule with an
    /// `arrow.up.right.circle` accessory to distinguish it from the tertiary
    /// "上次" caption above it.
    @ViewBuilder
    private func smartProgressionChip(_ advice: ProgressionAdvice) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(
                String(
                    format: String(
                        localized: "active_workout.smart_progression.chip_format",
                        defaultValue: "Suggested %1$@ × %2$lld",
                        comment: "SetRow smart-progression chip label. %1$@ is the formatted weight+unit (e.g. \"60kg\"), %2$lld is the reps count. Cataloged in Localizable.xcstrings by 006 T007."
                    ),
                    smartProgressionWeightSegment(advice.suggestedWeight),
                    Int64(advice.suggestedReps)
                )
            )
            .font(.caption)
            .foregroundStyle(.primary)
            Text(verbatim: "·")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(advice.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(Color.accentColor.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            String(
                localized: "active_workout.smart_progression.chip_a11y_hint",
                defaultValue: "Double-tap to fill weight and reps with the suggestion.",
                comment: "SetRow smart-progression chip VoiceOver hint. Communicates the tap-to-fill affordance (T006) so screen-reader users know activating the chip populates weight and reps. The primary spoken label — suggested weight, reps, and reason — is composed automatically by .accessibilityElement(children: .combine) from the visible Text children. Cataloged in Localizable.xcstrings by 006 T007."
            )
        )
    }

    /// Formats an advisor-suggested weight (canonical kg) for display in the
    /// chip, converting to the user's `WeightUnit` preference (mirrors the
    /// spec-004 caption path — FR-004) and re-using the caption-side
    /// integer / one-decimal formatter for visual consistency.
    private func smartProgressionWeightSegment(_ weightKg: Double) -> String {
        let display = weightUnit == .lb ? weightKg * 2.20462 : weightKg
        return "\(formatCaptionWeight(display))\(weightUnit.rawValue)"
    }

    // MARK: - Keyboard callbacks

    private func handleLeftAction(_ action: LeftKeyAction, field: SetField) {
        switch action {
        case .addPyramid:
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.exerciseAdded)
            #endif
            onAddSubSet(.pyramid)
        case .addDropSet:
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.exerciseAdded)
            #endif
            onAddSubSet(.dropSet)
        case .toggleUnilateral:
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.setCompleted)
            #endif
            exerciseSet.isUnilateral.toggle()
            if !exerciseSet.isUnilateral {
                exerciseSet.weightRight = nil
                weightRightText = ""
            }
        case .copyToNext:
            // MY-1073 reviewer P0: the audio input click emitted by the keyboard
            // is not sufficient — the acceptance criterion requires haptic
            // feedback for every left-column function key. `.exerciseAdded`
            // matches the semantic of "added another set-worth of data".
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.exerciseAdded)
            #endif
            onCopyToNext()
        }
    }

    private func handlePresetReps(weightKg: Double?, reps: Int) {
        if let weightKg {
            let displayWeight = weightUnit == .lb ? weightKg * 2.20462 : weightKg
            weightText = formatWeight(displayWeight)
            syncWeightToModel()
        }
        repsText = "\(reps)"
        syncRepsToModel()
    }

    private func syncWeightToModel() {
        let weight: Double
        if weightText.isEmpty {
            weight = 0
        } else {
            guard let parsed = Double(weightText) else { return }
            weight = parsed
        }
        guard weight.isFinite, weight >= 0 else { return }
        exerciseSet.weight = weightUnit == .lb ? weight / 2.20462 : weight
    }

    private func syncWeightRightToModel() {
        if weightRightText.isEmpty {
            exerciseSet.weightRight = nil
            return
        }
        guard let parsed = Double(weightRightText), parsed.isFinite, parsed >= 0 else { return }
        exerciseSet.weightRight = weightUnit == .lb ? parsed / 2.20462 : parsed
    }

    private func syncRepsToModel() {
        let reps: Int
        if repsText.isEmpty {
            reps = 0
        } else {
            guard let parsed = Int(repsText) else { return }
            reps = parsed
        }
        guard reps >= 0 else { return }
        exerciseSet.reps = reps
    }

    private func filterDecimalInput(_ text: String) -> String {
        var result = ""
        var hasDecimalPoint = false
        for char in text {
            if char.isNumber {
                result.append(char)
            } else if char == "." && !hasDecimalPoint {
                hasDecimalPoint = true
                result.append(char)
            }
        }
        return result
    }

    private func formatWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? (value == 0 ? "" : String(Int(value)))
            : String(format: "%.1f", value)
    }
}

// MARK: - Previews (MY-1091 row visual verification)
//
// Reviewer P0 for MY-1091 requires visual verification of normal vs. large
// row layout at COMPACT phone width (iPhone SE / Mini, 375pt), plus the
// unilateral overflow risk the AC calls out. These previews render `SetRow`
// through the real production code path — wrapping it in a `List` reproduces
// the row insets + section container, and seeding `activeWorkoutLargeMode`
// via `@AppStorage` before the wrapper initializes drives the same
// `ViewThatFits(in: .horizontal)` substitution production uses. The compact
// previews constrain the outer frame to 375pt so the ViewThatFits fallback
// path (`.largeCompact` widths) is exercised rather than the wide 110/88/88
// tokens that only fit landscape / Pro Max.

private struct SetRowPreviewWrapper: View {
    let unilateral: Bool
    let largeMode: Bool
    /// When non-nil, constrains the outer frame width so ViewThatFits
    /// substitutes the `.largeCompact` variant. `nil` lets the row expand
    /// to the preview canvas width (used by the "wide" previews below).
    let constrainedWidth: CGFloat?
    /// MY-1158 (T012): seed value for `ExerciseSet.rpe` so previews cover both
    /// the annotated (`rpe == 8`) and unannotated (`nil`) menu states without
    /// requiring a running app. The RPE picker lives in the row's ellipsis
    /// Menu, so the preview surface itself is unchanged — this exists so the
    /// SwiftData-seeded row round-trips both values.
    let rpe: Int?
    /// MY-1176 (spec 004-previous-set-hint T008): drives the previous-set
    /// caption previews. `.none` renders the row exactly as before (no
    /// caption, no reserved space — FR-003). `.bilateral` and `.unilateral`
    /// synthesize a same-index prior main set so the row exercises the
    /// caption path added in T005 (FR-001, FR-004).
    let previousSetKind: PreviousSetKind

    enum PreviousSetKind {
        case none
        case bilateral
        case unilateral
    }

    init(
        unilateral: Bool,
        largeMode: Bool,
        constrainedWidth: CGFloat? = nil,
        rpe: Int? = nil,
        previousSetKind: PreviousSetKind = .none
    ) {
        self.unilateral = unilateral
        self.largeMode = largeMode
        self.constrainedWidth = constrainedWidth
        self.rpe = rpe
        self.previousSetKind = previousSetKind
        UserDefaults.standard.set(largeMode, forKey: "activeWorkoutLargeMode")
    }

    var body: some View {
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        // Three-digit weight + a two-digit reps value stress the input widths
        // enough to expose overflow (unilateral) and truncation (bilateral).
        let sampleSet = ExerciseSet(
            order: 0,
            weight: 102.5,
            reps: 12,
            setType: .working,
            isUnilateral: unilateral,
            weightRight: unilateral ? 100 : nil,
            rpe: rpe
        )
        let previousSet: ExerciseSet? = {
            switch previousSetKind {
            case .none:
                return nil
            case .bilateral:
                return ExerciseSet(
                    order: 0,
                    weight: 100,
                    reps: 10,
                    setType: .working
                )
            case .unilateral:
                return ExerciseSet(
                    order: 0,
                    weight: 60,
                    reps: 8,
                    setType: .working,
                    isUnilateral: true,
                    weightRight: 58
                )
            }
        }()
        let list = List {
            Section {
                SetRow(
                    index: 0,
                    exerciseSet: sampleSet,
                    weightUnit: .kg,
                    canDelete: true,
                    exercise: exercise,
                    recentWeightKg: 100,
                    previousSet: previousSet,
                    onToggleCompleted: { _ in },
                    onDelete: {},
                    onAddSubSet: { _ in },
                    onCopyToNext: {}
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            } header: {
                Text(exercise.localizedName)
                    .font(LargeWorkoutFonts.exerciseName(large: largeMode))
            }
        }
        .listStyle(.plain)
        .modelContainer(try! ModelContainerConfiguration.makeTestContainer()) // swiftlint:disable:this force_try

        return Group {
            if let constrainedWidth {
                list.frame(width: constrainedWidth)
            } else {
                list
            }
        }
    }
}

// Compact (iPhone SE / Mini, 375pt) — exercises the ViewThatFits fallback.
#Preview("Row - Compact Normal") {
    SetRowPreviewWrapper(unilateral: false, largeMode: false, constrainedWidth: 375)
}

#Preview("Row - Compact Large Bilateral") {
    SetRowPreviewWrapper(unilateral: false, largeMode: true, constrainedWidth: 375)
}

#Preview("Row - Compact Large Unilateral (overflow guard)") {
    SetRowPreviewWrapper(unilateral: true, largeMode: true, constrainedWidth: 375)
}

// Wide (Pro Max / landscape) — exercises the primary wide ViewThatFits path.
#Preview("Row - Wide Large Bilateral") {
    SetRowPreviewWrapper(unilateral: false, largeMode: true)
}

#Preview("Row - Wide Large Unilateral") {
    SetRowPreviewWrapper(unilateral: true, largeMode: true)
}

// MY-1158 (spec 007-rpe-field T012): RPE coverage — rpe = 8 (annotated) and
// rpe = nil (unannotated). The picker lives in the ellipsis Menu so the row
// surface itself doesn't change, but the seeded `ExerciseSet.rpe` round-trips
// both states through the SwiftData model container in the preview so
// downstream consumers (AI prompt builder, exports) exercise both paths.
#Preview("Row - RPE Annotated (rpe = 8)") {
    SetRowPreviewWrapper(unilateral: false, largeMode: false, constrainedWidth: 375, rpe: 8)
}

#Preview("Row - RPE Not Set (rpe = nil)") {
    SetRowPreviewWrapper(unilateral: false, largeMode: false, constrainedWidth: 375, rpe: nil)
}

// MY-1176 (spec 004-previous-set-hint T008): previous-set caption previews.
// FR-003 requires that a nil `previousSet` renders no placeholder and reserves
// no extra vertical space, while a non-nil `previousSet` renders the tertiary
// "上次 …" caption directly under the row inputs (FR-001, FR-004). The pair
// below sits side-by-side in Xcode's preview navigator so the presence /
// absence of the caption line is directly comparable.
#Preview("Row - Previous Set (bilateral)") {
    SetRowPreviewWrapper(
        unilateral: false,
        largeMode: false,
        constrainedWidth: 375,
        previousSetKind: .bilateral
    )
}

#Preview("Row - Previous Set nil (no placeholder)") {
    SetRowPreviewWrapper(
        unilateral: false,
        largeMode: false,
        constrainedWidth: 375,
        previousSetKind: .none
    )
}

#Preview("Row - Previous Set (unilateral L/R)") {
    SetRowPreviewWrapper(
        unilateral: true,
        largeMode: false,
        constrainedWidth: 375,
        previousSetKind: .unilateral
    )
}
