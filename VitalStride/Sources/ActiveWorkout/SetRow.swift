// swiftlint:disable no_hardcoded_chinese
// Set Row (Always Editable).
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). Pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065). No semantic change.

import SwiftUI
import VitalModels
import VitalUI

struct SetRow: View {
    let index: Int
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let canDelete: Bool
    let onToggleCompleted: (_ wasCompleted: Bool) -> Void
    let onDelete: () -> Void
    let onAddSubSet: (_ type: SetType) -> Void

    @State private var weightText: String = ""
    @State private var weightRightText: String = ""
    @State private var repsText: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)

            if exerciseSet.isUnilateral {
                // MY-876: unilateral order matches bilateral "weight × reps":
                // left-weight / right-weight × reps. Reps stays at the tail so
                // the visual/accessibility sequence is consistent across modes.
                SelectAllTextField(
                    placeholder: weightUnit.rawValue,
                    text: $weightText,
                    keyboardType: .decimalPad
                )
                    .frame(width: 56)
                    .accessibilityLabel(String(
                        localized: "第 \(index + 1) 组左侧重量",
                        comment: "Left weight input a11y label"
                    ))
                    .accessibilityHint(String(localized: "输入左侧重量数值", comment: "Left weight input a11y hint"))
                    .onChange(of: weightText) { _, newValue in
                        let filtered = filterDecimalInput(newValue)
                        if filtered != newValue { weightText = filtered }
                        syncWeightToModel()
                    }

                Text("/")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                SelectAllTextField(
                    placeholder: weightUnit.rawValue,
                    text: $weightRightText,
                    keyboardType: .decimalPad
                )
                    .frame(width: 56)
                    .accessibilityLabel(String(
                        localized: "第 \(index + 1) 组右侧重量",
                        comment: "Right weight input a11y label"
                    ))
                    .accessibilityHint(String(localized: "输入右侧重量数值", comment: "Right weight input a11y hint"))
                    .onChange(of: weightRightText) { _, newValue in
                        let filtered = filterDecimalInput(newValue)
                        if filtered != newValue { weightRightText = filtered }
                        syncWeightRightToModel()
                    }

                Text("×")
                    .foregroundStyle(.secondary)

                SelectAllTextField(
                    placeholder: "次数",
                    text: $repsText,
                    keyboardType: .numberPad
                )
                    .frame(width: 60)
                    .accessibilityLabel("第 \(index + 1) 组次数")
                    .accessibilityHint("输入次数")
                    .onChange(of: repsText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { repsText = filtered }
                        syncRepsToModel()
                    }
            } else {
                SelectAllTextField(
                    placeholder: weightUnit.rawValue,
                    text: $weightText,
                    keyboardType: .decimalPad
                )
                    .frame(width: 70)
                    .accessibilityLabel("第 \(index + 1) 组重量")
                    .accessibilityHint("输入重量数值")
                    .onChange(of: weightText) { _, newValue in
                        let filtered = filterDecimalInput(newValue)
                        if filtered != newValue { weightText = filtered }
                        syncWeightToModel()
                    }

                Text("×")
                    .foregroundStyle(.secondary)

                SelectAllTextField(
                    placeholder: "次数",
                    text: $repsText,
                    keyboardType: .numberPad
                )
                    .frame(width: 60)
                    .accessibilityLabel("第 \(index + 1) 组次数")
                    .accessibilityHint("输入次数")
                    .onChange(of: repsText) { _, newValue in
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered != newValue { repsText = filtered }
                        syncRepsToModel()
                    }
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

                if exerciseSet.setType == .working {
                    Button {
                        onAddSubSet(.pyramid)
                    } label: {
                        Label(
                            String(localized: "添加递增组", comment: "Add pyramid subset menu item"),
                            systemImage: "arrow.up.right"
                        )
                    }
                    Button {
                        onAddSubSet(.dropSet)
                    } label: {
                        Label(
                            String(localized: "添加递减组", comment: "Add drop set subset menu item"),
                            systemImage: "arrow.down.right"
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

                Toggle(
                    String(localized: "单侧重量", comment: "Unilateral weight toggle in set menu"),
                    isOn: Binding(
                        get: { exerciseSet.isUnilateral },
                        set: { exerciseSet.isUnilateral = $0 }
                    )
                )
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, -4)
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
        // MY-877: rendered hit area stays 44pt (Constitution P1-H), but the
        // negative layout padding lets the button bleed into the row's
        // separator zone so the visible row height can target ~36pt.
        // SwiftUI hit-tests against rendered geometry, not layout claim.
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .padding(.vertical, -4)
        .accessibilityLabel("第 \(index + 1) 组，\(exerciseSet.isCompleted ? "已完成" : "未完成")")
        .accessibilityHint("双击切换完成状态")
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
