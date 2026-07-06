// swiftlint:disable no_hardcoded_chinese
// Set Row (Always Editable).
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). Pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065). MY-1073 wires each weight
// / reps input to the shared custom `WorkoutNumericKeyboard` and consolidates
// the previous Menu function items (pyramid / drop-set / unilateral toggle)
// into the keyboard's left column.

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
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void
    let onDelete: () -> Void
    let onAddSubSet: (_ type: SetType) -> Void
    /// MY-1073 — invoked when the keyboard's Copy key fires. The parent
    /// section covers/appends the next set as documented in the issue.
    let onCopyToNext: () -> Void

    @State private var weightText: String = ""
    @State private var weightRightText: String = ""
    @State private var repsText: String = ""
    // MY-1091: row-level Large Mode is driven off the same persisted flag the
    // toolbar toggle writes in MY-1088. @AppStorage observes the key so the
    // row re-renders when the toolbar toggles without any explicit
    // environment plumbing from ActiveWorkoutView.
    @AppStorage("activeWorkoutLargeMode") private var largeMode = false

    var body: some View {
        // MY-1091 P0 fix: wrap Large Mode's row in `ViewThatFits(in: .horizontal)`
        // so the wide 110/88/88 tokens render on Pro Max / landscape and the
        // compact 88/64/68 tokens render on iPhone SE / Mini (375pt content
        // width after 16pt list insets = 343pt). Normal mode has always fit
        // compact widths, so it skips the ViewThatFits wrapper entirely.
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

    init(unilateral: Bool, largeMode: Bool, constrainedWidth: CGFloat? = nil) {
        self.unilateral = unilateral
        self.largeMode = largeMode
        self.constrainedWidth = constrainedWidth
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
            weightRight: unilateral ? 100 : nil
        )
        let list = List {
            Section {
                SetRow(
                    index: 0,
                    exerciseSet: sampleSet,
                    weightUnit: .kg,
                    canDelete: true,
                    exercise: exercise,
                    recentWeightKg: 100,
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
