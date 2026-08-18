// swiftlint:disable no_hardcoded_chinese
// Sub-Set Row (Compact, Indented, Read-Only except delete — see MY-875 / MY-1420).
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). The pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065) migrates them. This split
// does not change localization semantics.
//
// MY-1420 partially reopens MY-875's read-only decision: sub-sets had no
// delete affordance at all, so a stray pyramid / drop-set row could only be
// removed by deleting its parent — which cascades and takes the freshly
// entered main-set data with it. Exactly one destructive action is opened up
// (delete); weight / reps / type / RPE stay read-only here and remain the
// parent `SetRow`'s job.

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
    /// MY-1420: inline delete. Mirrors `SetRow`'s menu entry so the two row
    /// kinds in the same list share one mental model; the trailing full swipe
    /// (attached in `ActiveExerciseSection`) is the fast path for the same
    /// action, and the menu is the discoverable one.
    let onDelete: () -> Void

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

            deleteMenu

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
            .accessibilityLabel(String(localized: "第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组，\(exerciseSet.isCompleted ? String(localized: "已完成", comment: "Set completion status: completed") : String(localized: "未完成", comment: "Set completion status: incomplete"))", comment: "A11y label composing parent set index and completion status"))
            .accessibilityHint(String(localized: "双击切换完成状态", comment: "A11y hint"))
        }
    }

    /// MY-1420: inline delete affordance.
    ///
    /// A bare `ellipsis` rather than `SetRow`'s `ellipsis.circle`: a sub-set is
    /// a secondary row, and dropping the ring keeps its visual weight below the
    /// main set it hangs under. `text3` for the same reason — this is a meta
    /// affordance, not row content. The menu carries exactly one item; the
    /// type / RPE pickers stay on `SetRow` (MY-875 read-only decision holds
    /// for everything but delete).
    ///
    /// Hit geometry follows MY-1013: the 44pt frame is a hit-test claim only,
    /// and row height stays compact via `ActiveExerciseSection`'s
    /// `listRowInsets` — no padding is added here that could inflate the row.
    private var deleteMenu: some View {
        Menu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(
                    String(localized: "删除", comment: "Delete sub-set menu item"),
                    systemImage: "trash"
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption)
                .foregroundStyle(theme.neutrals.text3)
                .frame(width: ActiveWorkoutHitTarget.side, height: ActiveWorkoutHitTarget.side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(String(
            localized: "第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组操作菜单",
            comment: "Sub-set action menu a11y label"
        ))
        .accessibilityHint(String(localized: "双击打开菜单", comment: "Sub-set action menu a11y hint"))
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
