// swiftlint:disable no_hardcoded_chinese
// Set Row (Always Editable).
// Extracted verbatim from ActiveWorkoutView.swift (MY-874). Pre-existing
// `no_hardcoded_chinese` literals move with the code and stay silenced at file
// scope until the dedicated i18n cleanup (MY-1065). MY-1073 wires each weight
// / reps input to the shared custom `WorkoutNumericKeyboard` and consolidates
// the previous Menu function items (pyramid / drop-set / unilateral toggle)
// into the keyboard's left column.

import DesignKit
import SwiftData
import SwiftUI
import TelemetryKit
import VitalModels
import VitalUI

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

/// Internal, inert by default. Observes descriptor/control geometry and the
/// mode action used by the row keyboard; it owns no training or selection state.
struct WorkoutRowObservation: Sendable {
    var descriptor: @MainActor @Sendable (AnyHashable, SetField, String, String, CGRect) -> Void = { _, _, _, _, _ in }
    var modeAction: @MainActor @Sendable (AnyHashable, @escaping @MainActor @Sendable () -> Void) -> Void = { _, _ in }
    var control: @MainActor @Sendable (AnyHashable, String, CGRect) -> Void = { _, _, _ in }
}

private struct WorkoutRowObservationKey: EnvironmentKey {
    static let defaultValue = WorkoutRowObservation()
}

extension EnvironmentValues {
    var workoutRowObservation: WorkoutRowObservation {
        get { self[WorkoutRowObservationKey.self] }
        set { self[WorkoutRowObservationKey.self] = newValue }
    }
}

struct WorkoutRowDescriptor: View {
    @Environment(\.workoutRowObservation) private var observation
    let row: AnyHashable
    let field: SetField
    let kind: String
    let text: String

    var body: some View {
        Text(text)
            .fixedSize()
            .allowsHitTesting(false)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                observation.descriptor(row, field, kind, text, frame)
            }
    }
}

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

    /// One extra point keeps native numeric fields at or above 44pt after
    /// SwiftUI rounds their UIKit-backed layout to the simulator pixel grid.
    static let numericInputSide: CGFloat = 45
}

/// Numeric inputs retain a real 44pt interactive height in compact mode.
/// Large Mode supplies its own larger field floor.
private struct NormalModeHitTargetPadding: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .frame(minHeight: ActiveWorkoutHitTarget.numericInputSide)
                .contentShape(Rectangle())
        } else {
            content
        }
    }
}

#if canImport(UIKit) && !os(macOS)
/// The shared coordinator keeps selection-aware editing and the custom keyboard
/// bridge. This row-owned host adds explicit sizing and Strata input colors, so
/// UIKit's intrinsic size cannot paint over the adjacent L/R label or reps box.
struct WorkoutSetInput: UIViewRepresentable {
    let input: SelectAllTextField
    let theme: Theme

    init(_ input: SelectAllTextField, theme: Theme) {
        self.input = input
        self.theme = theme
    }

    func makeCoordinator() -> SelectAllTextField.Coordinator { input.makeCoordinator() }

    func makeUIView(context: Context) -> UITextField {
        let view = UITextField()
        view.delegate = context.coordinator
        view.borderStyle = .none
        view.textAlignment = .center
        view.adjustsFontForContentSizeCategory = true
        view.adjustsFontSizeToFitWidth = true
        view.minimumFontSize = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addTarget(context.coordinator,
                       action: #selector(SelectAllTextField.Coordinator.textChanged(_:)), for: .editingChanged)
        context.coordinator.attach(textField: view)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: UITextField, context: Context) {
        if view.text != input.text { view.text = input.text }
        view.placeholder = ""
        if input.placeholder.isEmpty {
            view.attributedPlaceholder = nil
        } else {
            view.attributedPlaceholder = NSAttributedString(
                string: input.placeholder,
                attributes: [
                    .foregroundColor: UIColor(theme.primary.primary.opacity(0.72))
                ]
            )
        }
        view.font = input.font
        view.textColor = UIColor(theme.foreground)
        view.tintColor = UIColor(theme.accent)
        view.keyboardType = input.keyboardType
        context.coordinator.update(
            field: input.field, setType: input.setType, exercise: input.exercise,
            recentWeightKg: input.recentWeightKg,
            suggestedWeightKg: input.suggestedWeightKg,
            suggestedReps: input.suggestedReps,
            onLeftAction: input.onLeftAction,
            onPresetReps: input.onPresetReps,
            onFocusChange: input.onFocusChange
        )
        context.coordinator.installCustomKeyboardIfNeeded(on: view)
        context.coordinator.refreshCustomKeyboardContextIfInstalled()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 60, height: max(44, input.font.lineHeight + 12))
    }
}
#endif

struct SetRow: View {
    @Environment(\.workoutRowObservation) private var rowObservation
    let index: Int
    let exerciseSet: ExerciseSet
    let weightUnit: WeightUnit
    let canDelete: Bool
    /// Optional exercise context for the keyboard's preset resolver.
    let exercise: Exercise?
    /// Most recent same-exercise weight (kg) for the preset fallback chain.
    let recentWeightKg: Double?
    /// Kept for source compatibility with existing preview/caller fixtures.
    /// History is prefilled on add; no Prev column or caption is rendered.
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
    @State private var focusedField: SetField?
    @State private var showingRPEDialog = false
    // MY-1203 (spec 006-smart-progression T006): tap-to-fill + override
    // tracking. `pendingSuggestionSnapshot` holds the exact text values the
    // suggestion chip most recently filled in — when the row's weightText /
    // repsText later drift away from that snapshot, we know the user manually
    // edited the fields *after* tapping the chip. That transition flips
    // `suggestionOverridden` so T008 telemetry can distinguish
    // `suggestionAccepted` (tap-filled and left alone) from
    // `suggestionOverridden` (tap-filled and then re-edited). MY-1205 (T008)
    // extends the snapshot with the tap-filled advice's canonical ASCII
    // category so the metadata-only telemetry payload can carry it without
    // ever encoding weight / reps / localized reason text (Constitution I /
    // Quality Bar B). The snapshot is cleared once override is detected or
    // once `suggestionAccepted` fires on completion so subsequent edits do
    // not re-report; tapping the chip again resets both fields to the fresh
    // suggestion state. Values here are the display-side text (post-unit
    // conversion), NOT the canonical kg / raw reps — no additional value
    // logging or persistence beyond what the existing sync path already does.
    @State private var pendingSuggestionSnapshot: SuggestionFillSnapshot?
    @State private var suggestionOverridden: Bool = false

    private struct SuggestionFillSnapshot: Equatable {
        let weightText: String
        let weightRightText: String
        let repsText: String
        /// MY-1205 (spec 006-smart-progression T008): canonical ASCII category
        /// of the advice the user tap-filled — used as the `advice` telemetry
        /// parameter on `suggestionAccepted` / `suggestionOverridden`. This is
        /// *not* the advice's reason string (which is localized and would
        /// fragment metrics across locales, and is forbidden by Constitution I
        /// / Quality Bar B from carrying free-form text). Excluded from
        /// Equatable so drift detection stays scoped to the visible text.
        let adviceCategory: TelemetryIdentifier

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.weightText == rhs.weightText
                && lhs.weightRightText == rhs.weightRightText
                && lhs.repsText == rhs.repsText
        }
    }
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
    @Environment(\.theme) private var theme

    var body: some View {
        ViewThatFits(in: .horizontal) {
            rowContent(variant: largeMode ? .large : .normal, compact: false)
            rowContent(variant: .largeCompact, compact: false)
            rowContent(variant: .normal, compact: false)
            rowContent(variant: .normal, compact: true)
            if exerciseSet.isUnilateral {
                stackedRowContent.padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 56)
        // Only this background handles completion. Inputs and buttons above it
        // own their touches, so editing or opening More never completes a set.
        .background {
            Button(action: toggleCompleted) { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
        }
        .designSurface(style: .solid, cornerRadius: 16)
        .onAppear {
            refreshInputText()
            rowObservation.modeAction(exerciseSet.persistentModelID) {
                handleLeftAction(.toggleUnilateral, field: .weight)
            }
        }
        .onChange(of: weightUnit) { _, _ in refreshInputText() }
        .onChange(of: exerciseSet.weight) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.weightRight) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.reps) { _, _ in refreshInputText(preservingFocusedField: focusedField) }
        .onChange(of: exerciseSet.isUnilateral) { _, _ in refreshInputText() }
        .alert(String(localized: "workout.row.set_rpe", defaultValue: "Set RPE", comment: "RPE dialog title"),
               isPresented: $showingRPEDialog) {
            ForEach(6...10, id: \.self) { value in
                Button("\(value)") { exerciseSet.rpe = value }
            }
            Button(String(localized: "set_row_rpe_not_set", defaultValue: "Not set", comment: "Clear recorded RPE")) {
                exerciseSet.rpe = nil
            }
            Button(String(localized: "取消", comment: "Cancel"), role: .cancel) {}
        }
    }

    private func rowContent(variant: LargeWorkoutFieldWidth.Variant, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: compact ? 0 : 4) {
            completionButton
            inputFields(variant: variant, compact: compact)
            inlineMetadata(compact: compact)
            if !compact { Spacer(minLength: 0) }
            moreMenu
        }
        .padding(.horizontal, compact ? 0 : 4)
    }

    private var stackedRowContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                completionButton
                Spacer(minLength: 0)
                moreMenu
            }
            HStack(alignment: .center, spacing: 4) {
                inputFields(variant: .normal)
                inlineMetadata()
            }
        }
    }

    private func inputFields(variant: LargeWorkoutFieldWidth.Variant, compact: Bool = false) -> some View {
        let weightWidth = exerciseSet.isUnilateral
            ? LargeWorkoutFieldWidth.unilateralWeight(variant)
            : LargeWorkoutFieldWidth.bilateralWeight(variant)
        return HStack(spacing: compact ? 1 : 4) {
            let advice = smartProgressionAdvice()
            weightBox(binding: $weightText, field: .weight, width: weightWidth,
                      side: exerciseSet.isUnilateral ? "L" : String(localized: "workout.row.total_prefix", defaultValue: "Total", comment: "Bilateral total weight prefix"),
                      suggestion: advice, compact: compact)
            if exerciseSet.isUnilateral {
                weightBox(binding: $weightRightText, field: .weightRight, width: weightWidth, side: "R", suggestion: advice, compact: compact)
            }
            repsField(width: compact ? ActiveWorkoutHitTarget.numericInputSide : (variant == .large ? 64 : ActiveWorkoutHitTarget.numericInputSide), suggestion: advice, compact: compact)
        }
        .fixedSize(horizontal: !compact, vertical: false)
    }

    private func weightBox(binding: Binding<String>, field: SetField, width: CGFloat, side: String?, suggestion: ProgressionAdvice?, compact: Bool = false) -> some View {
        let isTotal = !exerciseSet.isUnilateral && field == .weight
        let fieldWidth = compact ? ActiveWorkoutHitTarget.numericInputSide : max(ActiveWorkoutHitTarget.numericInputSide, width - 28)
        return HStack(spacing: compact ? 0.5 : 2) {
            if let side {
                WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: field, kind: "prefix", text: side)
                    .font(compact ? .system(size: 7.5, weight: .medium) : .caption2.weight(isTotal ? .semibold : .bold))
                    .fixedSize()
                    .foregroundStyle(isTotal ? theme.neutrals.text3 : theme.accent)
                    .allowsHitTesting(false)
            }
            weightField(
                binding: binding, field: field, width: fieldWidth,
                a11yLabel: side == nil
                    ? String(localized: "第 \(index + 1) 组重量", comment: "Set weight")
                    : isTotal
                    ? String(localized: "第 \(index + 1) 组总重量", comment: "Total weight")
                    : (field == .weight
                       ? String(localized: "第 \(index + 1) 组左侧重量", comment: "Left weight")
                       : String(localized: "第 \(index + 1) 组右侧重量", comment: "Right weight")),
                a11yHint: String(localized: "输入重量数值", comment: "Enter weight"),
                suggestion: suggestion
            )
            WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: field, kind: "unit", text: weightUnit.rawValue)
                .font(compact ? .system(size: 7.5, weight: .medium) : .caption2.weight(.medium))
                .foregroundStyle(theme.neutrals.text3)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, compact ? 0 : 2)
        .background(theme.inner, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if focusedField == field {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.accent, lineWidth: 1.5)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var moreMenu: some View {
        Menu {
            if let advice = smartProgressionAdvice() {
                Button {
                    fillFromSuggestion(advice)
                } label: {
                    Label(
                        String(localized: "workout.keyboard.ai_suggest", defaultValue: "✨ AI", comment: "Apply smart progression suggestion"),
                        systemImage: "sparkles"
                    )
                }
            }
            Button { showingRPEDialog = true } label: {
                Label(String(localized: "workout.row.set_rpe", defaultValue: "Set RPE", comment: "Open RPE dialog"),
                      systemImage: "gauge.medium")
            }
            Picker(selection: Binding(get: { exerciseSet.setType }, set: { exerciseSet.setType = $0 })) {
                // Sub-sets are added through the keyboard, preserving the parent/child tree.
                Text(SetType.working.displayName).tag(SetType.working)
                Text(SetType.warmup.displayName).tag(SetType.warmup)
            } label: { Text(String(localized: "组类型", comment: "Set type")) }
            Button(action: onCopyToNext) {
                Label(String(localized: "workout_keyboard.copy_label", defaultValue: "Copy", comment: "Copy to next set"),
                      systemImage: "doc.on.doc")
            }
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(String(localized: "删除", comment: "Delete set"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.secondaryForeground)
                .frame(width: ActiveWorkoutHitTarget.side, height: ActiveWorkoutHitTarget.side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(String(localized: "第 \(index + 1) 组设置", comment: "Set configuration"))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            rowObservation.control(exerciseSet.persistentModelID, "menu", frame)
        }
    }

    private func refreshInputText(preservingFocusedField: SetField? = nil) {
        if preservingFocusedField != .weight {
            weightText = formatWeight(weightUnit == .lb ? exerciseSet.weight * 2.20462 : exerciseSet.weight)
        }
        if preservingFocusedField != .weightRight {
            let right = exerciseSet.weightRight ?? exerciseSet.weight
            weightRightText = exerciseSet.isUnilateral ? formatWeight(weightUnit == .lb ? right * 2.20462 : right) : ""
        }
        if preservingFocusedField != .reps {
            repsText = exerciseSet.reps == 0 ? "" : "\(exerciseSet.reps)"
        }
    }

    // MARK: - Row styling helpers

    /// Set-type badge in the SEED family (never semantic green/amber/red) so it
    /// doesn't collide with the orange rest-timer / success completion. Rendered
    /// only for non-working set types (warmup / drop-set / pyramid).
    private func setTypePill(_ type: SetType, compact: Bool = false) -> some View {
        let color = categoryColor(setTypeCategoryIndex(type), theme: theme)
        return Text(type.displayName)
            .font(compact ? .caption2.weight(.semibold) : TypeScale.meta.weight(.medium))
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 2 : 1)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
            .lineLimit(1)
            .minimumScaleFactor(compact ? 0.7 : 1)
            .fixedSize(horizontal: !compact, vertical: false)
            .frame(minWidth: compact ? 28 : 0)
            .frame(minWidth: compact ? 28 : 0)
    }

    private func inlineMetadata(compact: Bool = false) -> some View {
        HStack(spacing: compact ? 0 : 4) {
            HStack(spacing: compact ? 1 : 4) {
                if compact, exerciseSet.setType != .working, let rpe = exerciseSet.rpe {
                    Text("\(exerciseSet.setType.displayName) R\(rpe)")
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                        .foregroundStyle(categoryColor(setTypeCategoryIndex(exerciseSet.setType), theme: theme))
                        .background(categoryColor(setTypeCategoryIndex(exerciseSet.setType), theme: theme).opacity(0.16), in: Capsule())
                } else {
                    if exerciseSet.setType != .working {
                        setTypePill(exerciseSet.setType, compact: compact)
                    }
                    if let rpe = exerciseSet.rpe {
                        rpePill(rpe, compact: compact)
                    }
                }
            }
            // Preserve the short warm-up/RPE label when the suggestion also
            // needs room at the sidebar-constrained 375pt phone width.
            // Reserve the complete English Warm-up R8 at the compact font scale.
            .frame(minWidth: compact && (exerciseSet.setType != .working || exerciseSet.rpe != nil) ? 35 : nil)
            .allowsHitTesting(false)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                rowObservation.control(exerciseSet.persistentModelID, "metadata", frame)
            }
            if let advice = smartProgressionAdvice() {
                smartProgressionChip(advice, compact: compact)
            }
        }
    }

    private func rpePill(_ rpe: Int, compact: Bool = false) -> some View {
        Text(String(format: String(localized: "workout.row.rpe_value", defaultValue: "RPE %lld", comment: "Read-only recorded exertion"), Int64(rpe)))
            .font(compact ? .caption2.weight(.semibold).monospacedDigit() : TypeScale.meta.weight(.medium).monospacedDigit())
            .padding(.horizontal, compact ? 4 : 6)
            .padding(.vertical, compact ? 2 : 3)
            .background(theme.primary.primary.opacity(0.12), in: Capsule())
            .foregroundStyle(theme.primary.primary)
            .lineLimit(1)
            .minimumScaleFactor(compact ? 0.7 : 1)
            .fixedSize(horizontal: !compact, vertical: false)
    }

    /// Stable seed-family color index per set type (0..4 band from ProtoKit's
    /// `categoryColor`). Distinct per type so warmup / drop-set / pyramid read
    /// apart without ever using a semantic hue.
    private func setTypeCategoryIndex(_ type: SetType) -> Int {
        switch type {
        case .working: 0
        case .warmup: 2
        case .dropSet: 1
        case .pyramid: 3
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
        a11yHint: String,
        suggestion: ProgressionAdvice?
    ) -> some View {
        let weightPlaceholder = suggestion.map { advice in
            let displayWeight = weightUnit == .lb
                ? advice.suggestedWeight * 2.20462
                : advice.suggestedWeight
            return formatCaptionWeight(displayWeight)
        } ?? ""
        let weightHint = suggestion.map { "\(a11yHint)，\(smartProgressionSummaryText($0))" } ?? a11yHint
        #if canImport(UIKit) && !os(macOS)
        WorkoutSetInput(SelectAllTextField(
            placeholder: weightPlaceholder,
            text: binding,
            keyboardType: .decimalPad,
            font: inputUIFont,
            useCustomKeyboard: true,
            field: field,
            exercise: exercise,
            setType: exerciseSet.setType,
            recentWeightKg: recentWeightKg,
            suggestedWeightKg: suggestion?.suggestedWeight,
            suggestedReps: suggestion?.suggestedReps,
            onLeftAction: { action in handleLeftAction(action, field: field) },
            onPresetReps: { weightKg, reps in handlePresetReps(weightKg: weightKg, reps: reps) },
            onFocusChange: { newField in
                if let newField {
                    focusedField = newField
                } else if focusedField == field {
                    focusedField = nil
                    refreshInputText()
                }
            }
        ), theme: theme)
        .frame(width: width)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: largeMode ? LargeWorkoutFieldWidth.largeMinHeight : nil)
        .modifier(NormalModeHitTargetPadding(active: !largeMode))
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(weightHint)
        .accessibilityAction(named: suggestion.map { smartProgressionSummaryText($0) } ?? String(localized: "workout.keyboard.ai_suggest", defaultValue: "✨ AI", comment: "Apply smart progression suggestion")) {
            if let advice = suggestion {
                fillFromSuggestion(advice)
            }
        }
        .onChange(of: binding.wrappedValue) { _, newValue in
            let filtered = filterDecimalInput(newValue)
            if filtered != newValue { binding.wrappedValue = filtered }
            if field == .weight {
                syncWeightToModel()
            } else {
                syncWeightRightToModel()
            }
            noteSuggestionFieldEdit()
        }
        #else
        SelectAllTextField(
            placeholder: weightPlaceholder,
            text: binding,
            keyboardType: .decimalPad
        )
        .frame(width: width)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: largeMode ? LargeWorkoutFieldWidth.largeMinHeight : nil)
        .modifier(NormalModeHitTargetPadding(active: !largeMode))
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(weightHint)
        .accessibilityAction(named: suggestion.map { smartProgressionSummaryText($0) } ?? String(localized: "workout.keyboard.ai_suggest", defaultValue: "✨ AI", comment: "Apply smart progression suggestion")) {
            if let advice = suggestion {
                fillFromSuggestion(advice)
            }
        }
        .onChange(of: binding.wrappedValue) { _, newValue in
            let filtered = filterDecimalInput(newValue)
            if filtered != newValue { binding.wrappedValue = filtered }
            if field == .weight {
                syncWeightToModel()
            } else {
                syncWeightRightToModel()
            }
            noteSuggestionFieldEdit()
        }
        #endif
    }

    @ViewBuilder
    private func repsField(width: CGFloat, suggestion: ProgressionAdvice?, compact: Bool = false) -> some View {
        let repsPlaceholder = suggestion.map { "\($0.suggestedReps)" } ?? ""
        let editingHint = String(localized: "输入次数", comment: "Enter reps hint")
        let repsHint = suggestion.map { "\(editingHint)，\(smartProgressionSummaryText($0))" } ?? editingHint
        #if canImport(UIKit) && !os(macOS)
        HStack(spacing: compact ? 0.5 : 2) {
        WorkoutSetInput(SelectAllTextField(
            placeholder: repsPlaceholder,
            text: $repsText,
            keyboardType: .numberPad,
            font: inputUIFont,
            useCustomKeyboard: true,
            field: .reps,
            exercise: exercise,
            setType: exerciseSet.setType,
            recentWeightKg: recentWeightKg,
            suggestedWeightKg: suggestion?.suggestedWeight,
            suggestedReps: suggestion?.suggestedReps,
            onLeftAction: { action in handleLeftAction(action, field: .reps) },
            onPresetReps: { weightKg, reps in handlePresetReps(weightKg: weightKg, reps: reps) },
            onFocusChange: { newField in
                if let newField {
                    focusedField = newField
                } else if focusedField == .reps {
                    focusedField = nil
                    refreshInputText()
                }
            }
        ), theme: theme)
        .frame(width: width)
        .fixedSize(horizontal: true, vertical: false)
        .frame(minHeight: largeMode ? LargeWorkoutFieldWidth.largeMinHeight : nil)
        .modifier(NormalModeHitTargetPadding(active: !largeMode))
        .accessibilityLabel(String(localized: "第 \(index + 1) 组次数", comment: "Set reps a11y label"))
        .accessibilityHint(repsHint)
        .accessibilityAction(named: suggestion.map { smartProgressionSummaryText($0) } ?? String(localized: "workout.keyboard.ai_suggest", defaultValue: "✨ AI", comment: "Apply smart progression suggestion")) {
            if let advice = suggestion {
                fillFromSuggestion(advice)
            }
        }
        .onChange(of: repsText) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            if filtered != newValue { repsText = filtered }
            syncRepsToModel()
            noteSuggestionFieldEdit()
        }
        WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: .reps, kind: "unit",
                             text: String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit"))
            .font(compact ? .system(size: 7.5, weight: .medium) : .caption2.weight(.medium))
            .foregroundStyle(theme.neutrals.text3)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, compact ? 0 : 2)
        .background(theme.inner, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if focusedField == .reps {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.accent, lineWidth: 1.5)
            }
        }
        #else
        HStack(spacing: compact ? 0.5 : 2) {
            SelectAllTextField(
                placeholder: repsPlaceholder,
                text: $repsText,
                keyboardType: .numberPad
            )
            .frame(width: width)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: largeMode ? LargeWorkoutFieldWidth.largeMinHeight : nil)
            .modifier(NormalModeHitTargetPadding(active: !largeMode))
            WorkoutRowDescriptor(row: exerciseSet.persistentModelID, field: .reps, kind: "unit",
                             text: String(localized: "workout.row.reps_unit", defaultValue: "reps", comment: "Repetitions unit"))
                .font(compact ? .system(size: 7.5, weight: .medium) : .caption2.weight(.medium))
                .foregroundStyle(theme.neutrals.text3)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(String(localized: "第 \(index + 1) 组次数", comment: "Set reps a11y label"))
        .accessibilityHint(repsHint)
        .accessibilityAction(named: suggestion.map { smartProgressionSummaryText($0) } ?? String(localized: "workout.keyboard.ai_suggest", defaultValue: "✨ AI", comment: "Apply smart progression suggestion")) {
            if let advice = suggestion {
                fillFromSuggestion(advice)
            }
        }
        .onChange(of: repsText) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            if filtered != newValue { repsText = filtered }
            syncRepsToModel()
            noteSuggestionFieldEdit()
        }
        #endif
    }

    private func toggleCompleted() {
        let wasCompleted = exerciseSet.isCompleted
        exerciseSet.isCompleted = !wasCompleted
        if !wasCompleted {
            HapticManager.trigger(.setCompleted)
            // MY-1205 (spec 006-smart-progression T008 / FR-006):
            // completion is the save/commit point for the tap-fill →
            // "accepted" transition. If the user tap-filled the chip and
            // has not edited the fields since (snapshot still present,
            // override flag clear), record `suggestionAccepted` with the
            // recorded advice category and clear the snapshot so an
            // uncomplete/re-complete toggle can't double-report.
            if !suggestionOverridden, let snapshot = pendingSuggestionSnapshot {
                TelemetryService.shared.trackNonisolated(
                    .suggestionAccepted(advice: snapshot.adviceCategory)
                )
                pendingSuggestionSnapshot = nil
            }
        }
        onToggleCompleted(wasCompleted)
    }


    private var completionButton: some View {
        Button(action: toggleCompleted) {
            HStack(alignment: .center, spacing: 4) {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(theme.secondaryForeground)
                Image(systemName: exerciseSet.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(exerciseSet.isCompleted ? theme.success : theme.secondaryForeground)
            }
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
        .accessibilityLabel(String(localized: "第 \(index + 1) 组，\(exerciseSet.isCompleted ? String(localized: "已完成", comment: "Set completion status: completed") : String(localized: "未完成", comment: "Set completion status: incomplete"))", comment: "A11y label composing set index and completion status"))
        .accessibilityHint(String(localized: "双击切换完成状态", comment: "A11y hint"))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            rowObservation.control(exerciseSet.persistentModelID, "completion", frame)
        }
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

    private func smartProgressionSummaryText(_ advice: ProgressionAdvice) -> String {
        String(
            format: String(
                localized: "active_workout.smart_progression.chip_format",
                defaultValue: "Suggested %1$@ × %2$lld",
                comment: "Suggested weight with unit and reps for smart progression"
            ),
            smartProgressionWeightSegment(advice.suggestedWeight),
            Int64(advice.suggestedReps)
        )
    }

    /// Inline suggestion action. Applying it fills both inputs; subsequent
    /// manual edits retain the existing acceptance/override tracking.
    /// The chip is styled as a rounded capsule with a `sparkles` accessory
    /// to distinguish it from the tertiary "上次" caption above it.
    @ViewBuilder
    private func smartProgressionChip(_ advice: ProgressionAdvice, compact: Bool = false) -> some View {
        Button {
            fillFromSuggestion(advice)
        } label: {
            // MY-1208 (Constitution P1-H): route through the shared
            // `smartProgressionChipHitTargetContainer` so the invisible
            // tap region is measurably ≥44pt tall. Extracting the container
            // as an internal static lets `ActiveWorkoutHitTargetTests`
            // render it via UIHostingController and assert rendered height
            // — a regression that removes or shrinks the frame anywhere
            // along this path fails the test loudly.
            Self.smartProgressionChipHitTargetContainer {
                smartProgressionChipLabel(advice, compact: compact)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(smartProgressionSummaryText(advice) + ". " + advice.reason)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            rowObservation.control(exerciseSet.persistentModelID, "suggestion", frame)
        }
        .accessibilityHint(
            String(
                localized: "active_workout.smart_progression.chip_a11y_hint",
                defaultValue: "Double-tap to fill weight and reps with the suggestion.",
                comment: "SetRow smart-progression chip VoiceOver hint. Communicates the tap-to-fill affordance (T006) so screen-reader users know activating the chip populates weight and reps. The primary spoken label — suggested weight, reps, and reason — is composed automatically by .accessibilityElement(children: .combine) from the visible Text children. Cataloged in Localizable.xcstrings by 006 T007."
            )
        )
    }

    /// MY-1208 (Constitution P1-H): wraps the visible compact-capsule chip
    /// label in a fixed-height frame ≥ `ActiveWorkoutHitTarget.side` (44pt)
    /// with `contentShape(Rectangle())` so the invisible tap region — the
    /// actual hit target — meets the HIG floor without inflating the drawn
    /// capsule padding/background. Exposed as `internal static` so
    /// `ActiveWorkoutHitTargetTests` can render this exact container over a
    /// deliberately tiny (< 44pt) label and assert the *rendered* height
    /// stays ≥ 44pt: if a future refactor deletes or shrinks the frame
    /// here, the rendered measurement collapses to the label's intrinsic
    /// height and the test fails loudly.
    @ViewBuilder
    static func smartProgressionChipHitTargetContainer<Label: View>(
        @ViewBuilder label: () -> Label
    ) -> some View {
        label()
            .frame(minHeight: ActiveWorkoutHitTarget.side, alignment: .leading)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func smartProgressionChipLabel(_ advice: ProgressionAdvice, compact: Bool = false) -> some View {
        if compact {
            let displayWeight = weightUnit == .lb
                ? advice.suggestedWeight * 2.20462
                : advice.suggestedWeight
            let label = "\(formatCaptionWeight(displayWeight))×\(advice.suggestedReps)"
            HStack(spacing: 0.5) {
                // Bound the decorative symbol so it cannot consume the
                // numeric label's minimum readable width on a 375pt phone.
                Image(systemName: "sparkles")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 6, height: 8)
                    .foregroundStyle(theme.primary.primary)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 8).monospacedDigit())
                    .foregroundStyle(theme.neutrals.text1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 2)
            .frame(width: compactSuggestionWidth(label))
            .background(Capsule().fill(theme.primary.primary.opacity(0.12)))
            .contentShape(Capsule())
        } else {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(theme.primary.primary)
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
                .foregroundStyle(theme.neutrals.text1)
                Text(verbatim: "·")
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text2)
                    .accessibilityHidden(true)
                Text(advice.reason)
                    .font(.caption)
                    .foregroundStyle(theme.neutrals.text2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(theme.primary.primary.opacity(0.12))
            )
            .contentShape(Capsule())
        }
    }

    /// Give the compact label its full numeric ink width at minimum scale.
    /// A fixed proposal also keeps ViewThatFits from reserving its unscaled
    /// ideal width while compressing the adjacent Warm-up/RPE label.
    private func compactSuggestionWidth(_ text: String) -> CGFloat? {
        #if canImport(UIKit) && !os(macOS)
        let font = UIFont.monospacedDigitSystemFont(ofSize: 8, weight: .regular)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth * 0.55 + 6 + 0.5 + 2)
        #else
        return nil
        #endif
    }

    /// MY-1203 (T006): populates the row's editable weight/reps inputs from
    /// `advice`, then records a snapshot of the just-filled text so later
    /// text-field edits can flip `suggestionOverridden`. Any pending override
    /// state is reset — re-tapping the chip means the user is re-accepting
    /// the suggestion. Weight is converted from canonical kg (advisor output)
    /// to the row's current `weightUnit` so the shown value matches the chip.
    /// For unilateral rows the same suggested load is mirrored to both sides
    /// (the advisor works on the row-level "load" concept and does not split
    /// L/R); a follow-up manual per-side edit still counts as an override.
    private func fillFromSuggestion(_ advice: ProgressionAdvice) {
        let displayWeight = weightUnit == .lb
            ? advice.suggestedWeight * 2.20462
            : advice.suggestedWeight
        let filledWeightText = formatWeight(displayWeight)
        let filledRepsText = advice.suggestedReps == 0 ? "" : "\(advice.suggestedReps)"

        suggestionOverridden = false
        weightText = filledWeightText
        repsText = filledRepsText
        if exerciseSet.isUnilateral {
            weightRightText = filledWeightText
            syncWeightRightToModel()
        }
        syncWeightToModel()
        syncRepsToModel()

        pendingSuggestionSnapshot = SuggestionFillSnapshot(
            weightText: filledWeightText,
            weightRightText: exerciseSet.isUnilateral ? filledWeightText : "",
            repsText: filledRepsText,
            adviceCategory: Self.telemetryCategory(for: advice)
        )
    }

    /// MY-1205 (spec 006-smart-progression T008): called from the weight / reps
    /// `onChange` handlers after the value has been normalized (decimal-
    /// filtered / digit-only) and synced to the model. When there's a pending
    /// suggestion snapshot and the current text no longer matches it, the user
    /// has manually edited a field after tapping the chip — flip the override
    /// flag, emit the `suggestionOverridden` telemetry with the recorded
    /// advice category, and drop the snapshot so subsequent edits don't
    /// re-report.
    private func noteSuggestionFieldEdit() {
        guard let snapshot = pendingSuggestionSnapshot else { return }
        let textChanged = weightText != snapshot.weightText
            || weightRightText != snapshot.weightRightText
            || repsText != snapshot.repsText
        if textChanged {
            suggestionOverridden = true
            pendingSuggestionSnapshot = nil
            TelemetryService.shared.trackNonisolated(
                .suggestionOverridden(advice: snapshot.adviceCategory)
            )
        }
    }

    /// MY-1205 (spec 006-smart-progression T008): maps a `ProgressionAdvice`
    /// case to the canonical ASCII category identifier carried by the
    /// `suggestion_accepted` / `suggestion_overridden` telemetry events.
    /// The localized `reason` string is deliberately NOT used — Constitution I
    /// / Quality Bar B forbid free-form or locale-dependent text on the wire,
    /// and remote analytics fragment by parameter value.
    private static func telemetryCategory(for advice: ProgressionAdvice) -> TelemetryIdentifier {
        switch advice {
        case .maintain: "maintain"
        case .increaseWeight: "increase_weight"
        case .increaseReps: "increase_reps"
        case .decreaseWeight: "decrease_weight"
        }
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
        case .addDropSet:
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.exerciseAdded)
            #endif
            onAddSubSet(.dropSet)
        case .toggleUnilateral:
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.setCompleted)
            #endif
            Self.toggleExerciseWeightMode(from: exerciseSet)
            refreshInputText()
        case .setWarmup:
            exerciseSet.setType = exerciseSet.setType == .warmup ? .working : .warmup
        case .addSet:
            if let owner = exerciseSet.workoutExercise {
                _ = ActiveExerciseSection.insertAppendedMainSet(in: owner, using: modelContext)
            }
        case .toggleWeightUnit:
            let next: WeightUnit = weightUnit == .kg ? .lb : .kg
            UserDefaults.standard.set(next.rawValue, forKey: "weightUnit")
        case .copyToNext:
            // MY-1073 reviewer P0: the audio input click emitted by the keyboard
            // is not sufficient — the acceptance criterion requires haptic
            // feedback for every left-column function key. `.exerciseAdded`
            // matches the semantic of "added another set-worth of data".
            #if canImport(UIKit) && !os(macOS)
            HapticManager.trigger(.exerciseAdded)
            #endif
            onCopyToNext()
        case .applyAISuggestion:
            if let advice = smartProgressionAdvice() {
                fillFromSuggestion(advice)
            }
        }
    }

    /// A mode key always applies to every row of the owning exercise, including sub-sets.
    static func toggleExerciseWeightMode(from set: ExerciseSet) {
        let unilateral = !set.isUnilateral
        for row in set.workoutExercise?.sets ?? [set] {
            row.isUnilateral = unilateral
            if unilateral, row.weightRight == nil { row.weightRight = row.weight }
            // Keep an entered right-hand load when returning to total mode. Switching
            // back restores it instead of silently discarding recorded training data.
        }
    }

    private func handlePresetReps(weightKg: Double?, reps: Int) {
        if let weightKg {
            let displayWeight = weightUnit == .lb ? weightKg * 2.20462 : weightKg
            weightText = formatWeight(displayWeight)
            if exerciseSet.isUnilateral {
                weightRightText = formatWeight(displayWeight)
                syncWeightRightToModel()
            }
            syncWeightToModel()
        }
        repsText = "\(reps)"
        syncRepsToModel()
        refreshInputText()
    }

    private func syncWeightToModel() {
        let current = weightUnit == .lb ? exerciseSet.weight * 2.20462 : exerciseSet.weight
        guard weightText != formatWeight(current) else { return }
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
        let current = exerciseSet.weightRight ?? exerciseSet.weight
        guard weightRightText != formatWeight(weightUnit == .lb ? current * 2.20462 : current) else { return }
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
            nameZh: String(localized: "卧推", comment: ""),
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
        .designThemePreview()
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

// MARK: - Smart Progression suggestion-state previews (MY-1210 / spec 006 T009)
//
// Renders SetRow with the Smart Progression chip in two of its shipped
// states so the T007 UI copy, T006 tap-to-fill affordance, and the
// no-history FR-004 edge case can be visually spot-checked from Xcode's
// preview canvas without running the app.
//
// - `.increaseWeightSuggestion` seeds a completed prior workout whose
//   three main sets all hit the upper bound of the default 8...12 rep
//   range at 60 kg. `SmartProgressionAdvisor.suggest(...)` therefore
//   returns `.increaseWeight` and the chip renders as "Suggested 65kg × 8"
//   (chest exercise → +5 kg archetype). The current in-progress workout
//   is inserted into the same in-memory container and its ExerciseSet is
//   wired through `workoutExercise -> workout` so `smartProgressionAdvice()`
//   reaches the seeded history.
// - `.noHistoryNoChip` inserts the current in-progress workout but no
//   prior workouts, so `PreviousSetLookup.previousMainSet(...)` returns
//   nil, the advisor returns nil, and the chip omits itself — matching
//   the FR-004 no-history behavior.
//
// The previews are pure UI: no telemetry is emitted (the tap-fill
// telemetry path is only reached when a user activates the chip), no
// HealthKit is queried, and the seeded reps / weight values are
// preview fixtures — not real training values from any user.
private struct SmartProgressionPreviewWrapper: View {
    enum ProgressionState {
        case increaseWeightSuggestion
        case noHistoryNoChip
    }

    let state: ProgressionState

    var body: some View {
        // swiftlint:disable:next force_try
        let container = try! ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext

        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: String(localized: "卧推", comment: ""),
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)

        let now = Date()
        let currentWorkout = Workout(
            type: .strength,
            startDate: now,
            endDate: nil
        )
        context.insert(currentWorkout)

        let currentExercise = WorkoutExercise(order: 0)
        currentExercise.workout = currentWorkout
        currentExercise.exercise = exercise
        context.insert(currentExercise)

        let currentSet = ExerciseSet(
            order: 0,
            weight: 60,
            reps: 0,
            setType: .working
        )
        currentSet.workoutExercise = currentExercise
        context.insert(currentSet)

        if state == .increaseWeightSuggestion {
            let priorStart = now.addingTimeInterval(-86_400)
            let priorEnd = priorStart.addingTimeInterval(3_600)
            let priorWorkout = Workout(
                type: .strength,
                startDate: priorStart,
                endDate: priorEnd
            )
            context.insert(priorWorkout)

            let priorExercise = WorkoutExercise(order: 0)
            priorExercise.workout = priorWorkout
            priorExercise.exercise = exercise
            context.insert(priorExercise)

            for index in 0..<3 {
                let priorSet = ExerciseSet(
                    order: index,
                    weight: 60,
                    reps: 12,
                    setType: .working,
                    isCompleted: true
                )
                priorSet.workoutExercise = priorExercise
                context.insert(priorSet)
            }
        }

        do {
            try context.save()
        } catch {
            // Preview-only in-memory container; surfacing the error keeps the
            // preview visible even if a schema seed goes wrong in development.
            assertionFailure("Preview seed save failed: \(error)")
        }

        return List {
            Section {
                SetRow(
                    index: 0,
                    exerciseSet: currentSet,
                    weightUnit: .kg,
                    canDelete: true,
                    exercise: exercise,
                    recentWeightKg: 60,
                    onToggleCompleted: { _ in },
                    onDelete: {},
                    onAddSubSet: { _ in },
                    onCopyToNext: {}
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            } header: {
                Text(exercise.localizedName)
                    .font(LargeWorkoutFonts.exerciseName(large: false))
            }
        }
        .listStyle(.plain)
        .frame(width: 375)
        .modelContainer(container)
        .designThemePreview()
    }
}

#Preview("Row - Smart Progression (increase weight)") {
    SmartProgressionPreviewWrapper(state: .increaseWeightSuggestion)
}

#Preview("Row - Smart Progression (no history, no chip)") {
    SmartProgressionPreviewWrapper(state: .noHistoryNoChip)
}
