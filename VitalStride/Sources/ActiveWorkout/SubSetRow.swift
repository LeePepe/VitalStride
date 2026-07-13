// swiftlint:disable no_hardcoded_chinese
// Sub-Set Row (Compact, Indented, Read-Only — see MY-875).
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). The pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065) migrates them. This split
// does not change localization semantics.

import DesignKit
import SwiftUI
import VitalModels
import VitalUI

struct SubSetRow: View {
    @Environment(\.theme) private var theme
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let isLast: Bool
    let parentSetNumber: Int
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            treeLine
                .accessibilityHidden(true)

            if exerciseSet.isUnilateral {
                // MY-876: SubSet read-only order matches bilateral
                // "weight × reps": left-weight / right-weight × reps.
                Text(weightDisplay(exerciseSet.weight))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text2)
                    .frame(width: 50, alignment: .center)
                    .accessibilityLabel(String(
                        localized: "第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组左侧重量",
                        comment: "SubSet left weight a11y label"
                    ))
                    .accessibilityValue("\(weightDisplay(exerciseSet.weight)) \(weightUnit.rawValue)")

                Text("/")
                    .font(.footnote)
                    .foregroundStyle(theme.neutrals.text2)
                    .accessibilityHidden(true)

                Text(weightDisplay(exerciseSet.weightRight ?? exerciseSet.weight))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text2)
                    .frame(width: 50, alignment: .center)
                    .accessibilityLabel(String(
                        localized: "第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组右侧重量",
                        comment: "SubSet right weight a11y label"
                    ))
                    .accessibilityValue(
                        "\(weightDisplay(exerciseSet.weightRight ?? exerciseSet.weight)) \(weightUnit.rawValue)"
                    )

                Text("×")
                    .font(.footnote)
                    .foregroundStyle(theme.neutrals.text2)
                    .accessibilityHidden(true)

                Text(repsDisplay)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text2)
                    .frame(width: 52, alignment: .center)
                    .accessibilityLabel(String(
                        localized: "第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组次数",
                        comment: "SubSet reps a11y label"
                    ))
                    .accessibilityValue(repsDisplay)
            } else {
                Text(weightDisplay(exerciseSet.weight))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text2)
                    .frame(width: 62, alignment: .center)
                    .accessibilityLabel(String(
                        localized: "第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组重量",
                        comment: "SubSet weight a11y label"
                    ))
                    .accessibilityValue("\(weightDisplay(exerciseSet.weight)) \(weightUnit.rawValue)")

                Text("×")
                    .font(.footnote)
                    .foregroundStyle(theme.neutrals.text2)
                    .accessibilityHidden(true)

                Text(repsDisplay)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(theme.neutrals.text2)
                    .frame(width: 52, alignment: .center)
                    .accessibilityLabel(String(
                        localized: "第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组次数",
                        comment: "SubSet reps a11y label"
                    ))
                    .accessibilityValue(repsDisplay)
            }

            Text(exerciseSet.setType.displayName)
                .font(.caption)
                .foregroundStyle(exerciseSet.setType.labelColor(theme: theme))
                .frame(width: 44, alignment: .leading)
                .accessibilityLabel(exerciseSet.setType.displayName)

            Spacer()

            Button {
                let wasCompleted = exerciseSet.isCompleted
                exerciseSet.isCompleted = !wasCompleted
                if !wasCompleted {
                    HapticManager.trigger(.setCompleted)
                }
                onToggleCompleted(wasCompleted)
            } label: {
                Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(exerciseSet.isCompleted ? theme.success : theme.neutrals.text2)
            }
            .buttonStyle(.borderless)
            // MY-1013: unambiguous 44pt hit target (Constitution P1-H). The
            // prior `.padding(.vertical, -8)` on top of a 44pt frame let the
            // rendered button overhang two rows above and below, so hit-test
            // and VoiceOver focus geometry were ambiguous. Row-level insets
            // in ActiveExerciseSection keep the SubSet row visually compact
            // without compressing the button's layout claim.
            .frame(width: ActiveWorkoutHitTarget.side, height: ActiveWorkoutHitTarget.side)
            .contentShape(Rectangle())
            // swiftlint:disable:next line_length
            .accessibilityLabel("第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组，\(exerciseSet.isCompleted ? "已完成" : "未完成")")
            .accessibilityHint("双击切换完成状态")
        }
    }

    private var treeLine: some View {
        HStack(spacing: 2) {
            Text(isLast ? "└─" : "├─")
                .font(.caption.monospaced())
                .foregroundStyle(theme.neutrals.text3)
        }
        .frame(width: 28, alignment: .leading)
    }

    private var repsDisplay: String {
        exerciseSet.reps == 0 ? "—" : "\(exerciseSet.reps)"
    }

    private func weightDisplay(_ weightKg: Double) -> String {
        let displayValue = weightUnit == .lb ? weightKg * 2.20462 : weightKg
        return formatWeight(displayValue)
    }

    private func formatWeight(_ value: Double) -> String {
        if value == 0 { return "—" }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}
