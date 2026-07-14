import DesignKit
import SwiftUI
import VitalModels

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

// MARK: - Public model types

/// Which field of an `ExerciseSet` the keyboard is currently editing.
///
/// * `weight` / `weightRight` are the primary "left" and "right" weight inputs
///   (right only shows for unilateral sets). Decimal point is enabled.
/// * `reps` is an integer input. Decimal point is disabled.
enum SetField: String, Equatable, Sendable, CaseIterable {
    case weight
    case weightRight
    case reps

    /// Whether the keypad's decimal key should be enabled for this field.
    var isDecimalEnabled: Bool {
        switch self {
        case .weight, .weightRight: true
        case .reps: false
        }
    }

    /// Whether this field represents a weight value (either left or right).
    var isWeightField: Bool {
        self == .weight || self == .weightRight
    }
}

/// Left-column function-key actions. The keyboard only reports them via a
/// callback — Stage 3 (SetRow / ActiveWorkoutView) is responsible for the
/// actual model mutation.
enum LeftKeyAction: String, Equatable, Sendable, CaseIterable {
    /// Add a pyramid (ascending) sub-set. Only enabled for `SetType.working`.
    case addPyramid
    /// Add a drop-set (descending) sub-set. Only enabled for `SetType.working`.
    case addDropSet
    /// Toggle between bilateral and unilateral weight entry.
    case toggleUnilateral
    /// Copy the current set's values to the next set.
    case copyToNext
}

// MARK: - SwiftUI content view

#if canImport(UIKit) && !os(macOS)

/// SwiftUI content view rendered inside `WorkoutNumericKeyboard`.
///
/// Renders three columns (spec: iPad ≤ 280pt / iPhone ≤ 260pt tall):
/// * left: 4 stacked function keys (pyramid / drop-set / uni-toggle / copy)
/// * center: the shared `NumericKeypad` digit grid
/// * right: 3 stacked preset-reps keys (15-20 / 8-12 / 4-6) + a Done key.
///
/// This view is fully deterministic from its inputs — the containing
/// `UIView` subclass drives layout / autolayout / audio feedback.
struct WorkoutNumericKeyboardContentView: View {
    let field: SetField
    let setType: SetType
    let exercise: Exercise?
    let recentWeightKg: Double?
    /// Explicit theme injected by the enclosing `WorkoutNumericKeyboard`
    /// host. `inputView` is a detached UIKit hierarchy and does not inherit
    /// the app-root `.designTheme(...)` environment, so the host resolves the
    /// theme itself (seed: teal, isDark: from trait collection) and pushes it
    /// through the environment for descendants (e.g. `NumericKeypad`).
    let theme: Theme
    let onKeyPress: @MainActor (NumericKeypadKey) -> Void
    let onLeftAction: @MainActor (LeftKeyAction) -> Void
    let onPresetReps: @MainActor (_ weightKg: Double?, _ reps: Int) -> Void
    let onDone: @MainActor () -> Void

    /// Local cycling state: last reps value tapped per bucket. Persists
    /// across taps so repeat presses walk through the cycle.
    @State private var lastRepsByBucket: [PresetRepBucket: Int] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            leftColumn
                .frame(maxWidth: 84)
            centerColumn
                .frame(maxWidth: .infinity)
            rightColumn
                .frame(maxWidth: 84)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(theme.neutrals.bg)
        .environment(\.theme, theme)
        .accessibilityElement(children: .contain)
    }

    // MARK: Left column — function keys

    private var leftColumn: some View {
        VStack(spacing: 6) {
            functionKey(
                .addPyramid,
                label: "+↑",
                a11y: String(localized: "workout_keyboard.add_pyramid_a11y", defaultValue: "Add ascending sub-set", comment: "Workout keyboard: add pyramid sub-set")
            )
            functionKey(
                .addDropSet,
                label: "+↓",
                a11y: String(localized: "workout_keyboard.add_drop_set_a11y", defaultValue: "Add drop-set sub-set", comment: "Workout keyboard: add drop-set sub-set")
            )
            functionKey(
                .toggleUnilateral,
                label: String(localized: "workout_keyboard.toggle_unilateral_label", defaultValue: "Uni/Total", comment: "Workout keyboard: unilateral/bilateral toggle key label"),
                a11y: String(localized: "workout_keyboard.toggle_unilateral_a11y", defaultValue: "Toggle unilateral or bilateral input", comment: "Workout keyboard: toggle unilateral/bilateral input")
            )
            functionKey(
                .copyToNext,
                label: String(localized: "workout_keyboard.copy_label", defaultValue: "Copy", comment: "Workout keyboard: copy-to-next key label"),
                a11y: String(localized: "workout_keyboard.copy_to_next_a11y", defaultValue: "Copy values to next set", comment: "Workout keyboard: copy values to next set")
            )
        }
    }

    private func functionKey(
        _ action: LeftKeyAction,
        label: String,
        a11y: String
    ) -> some View {
        let enabled = isEnabled(action)
        return Button {
            onLeftAction(action)
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.6))
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(a11y)
        .accessibilityHint(enabled ? "" : String(localized: "workout_keyboard.disabled_hint", defaultValue: "This key is unavailable for the current set type", comment: "Workout keyboard: disabled key hint"))
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private func isEnabled(_ action: LeftKeyAction) -> Bool {
        switch action {
        case .addPyramid, .addDropSet: setType == .working
        case .toggleUnilateral, .copyToNext: true
        }
    }

    // MARK: Center column — digit grid + Done row

    private var centerColumn: some View {
        VStack(spacing: 6) {
            NumericKeypad(mode: keypadMode, onKeyPress: onKeyPress)
        }
    }

    private var keypadMode: NumericKeypadMode {
        field.isDecimalEnabled ? .decimal : .integer
    }

    // MARK: Right column — preset reps + Done

    private var rightColumn: some View {
        VStack(spacing: 6) {
            presetKey(
                .high,
                label: "15-20",
                a11y: String(localized: "workout_keyboard.preset_high_a11y", defaultValue: "15 to 20 reps preset", comment: "Workout keyboard: 15-20 reps preset")
            )
            presetKey(
                .mid,
                label: "8-12",
                a11y: String(localized: "workout_keyboard.preset_mid_a11y", defaultValue: "8 to 12 reps preset", comment: "Workout keyboard: 8-12 reps preset")
            )
            presetKey(
                .low,
                label: "4-6",
                a11y: String(localized: "workout_keyboard.preset_low_a11y", defaultValue: "4 to 6 reps preset", comment: "Workout keyboard: 4-6 reps preset")
            )
            doneKey
        }
    }

    private func presetKey(_ bucket: PresetRepBucket, label: String, a11y: String) -> some View {
        Button {
            let previous = lastRepsByBucket[bucket]
            let result = ExerciseDefaults.resolvePreset(
                bucket: bucket,
                exercise: exercise,
                recentWeightKg: recentWeightKg,
                previousReps: previous
            )
            lastRepsByBucket[bucket] = result.reps
            onPresetReps(result.weightKg, result.reps)
        } label: {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private var doneKey: some View {
        Button {
            onDone()
        } label: {
            Text(String(localized: "workout_keyboard.done_label", defaultValue: "Done", comment: "Workout keyboard: Done key label"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "workout_keyboard.done_a11y", defaultValue: "Finish input", comment: "Workout keyboard: Done key a11y label"))
        .accessibilityAddTraits(.isKeyboardKey)
    }
}

// MARK: - UIView container

/// Custom keyboard view intended to be assigned as `UITextField.inputView`.
///
/// Stage 2 delivers the standalone component + preview; Stage 3 will actually
/// wire it into `SelectAllTextField` / `SetRow`. Consumers construct the view
/// with the current field/exercise context and callback closures.
///
/// The class subclasses `UIView` (per spec) instead of `UIInputView` because
/// `UIHostingController`'s SwiftUI content already handles its own background
/// and safe-area handling; the `enableInputClicksWhenVisible` protocol
/// requirement is satisfied at the type level and audio feedback is emitted
/// through `UIDevice.playInputClick()` on each key press.
final class WorkoutNumericKeyboard: UIView, UIInputViewAudioFeedback {

    // MARK: State

    private var field: SetField
    private var setType: SetType
    private var exercise: Exercise?
    private var recentWeightKg: Double?
    private let onKeyPress: @MainActor (NumericKeypadKey) -> Void
    private let onLeftAction: @MainActor (LeftKeyAction) -> Void
    private let onPresetReps: @MainActor (_ weightKg: Double?, _ reps: Int) -> Void
    private let onDone: @MainActor () -> Void

    /// SwiftUI hosting controller — retained so its view stays anchored while
    /// the keyboard is on-screen.
    private let host: UIHostingController<WorkoutNumericKeyboardContentView>

    /// Height constraint applied on install. iPad ≤ 280pt / iPhone ≤ 260pt.
    private var heightConstraint: NSLayoutConstraint?

    // MARK: UIInputViewAudioFeedback

    var enableInputClicksWhenVisible: Bool { true }

    // MARK: Theme resolution

    /// Seed used for the keyboard's theme. Matches the app-root
    /// `.designTheme(seed: .teal, ...)` in `VitalStrideApp` so the inputView
    /// renders in the same palette as the rest of the app.
    private static let seed: Seed = .teal
    private static let neutral: Neutral = .slate

    /// Resolve the theme for the current trait collection. `inputView` is a
    /// detached UIKit hierarchy that does not inherit the SwiftUI environment,
    /// so we compute `isDark` from the view's own trait collection and hand
    /// the resulting `Theme` down as an explicit value.
    static func resolveTheme(isDark: Bool) -> Theme {
        Theme(seed: seed, neutral: neutral, isDark: isDark)
    }

    private func currentIsDark() -> Bool {
        traitCollection.userInterfaceStyle == .dark
    }

    // MARK: Init

    init(
        field: SetField,
        setType: SetType,
        exercise: Exercise?,
        recentWeightKg: Double?,
        onKeyPress: @escaping @MainActor (NumericKeypadKey) -> Void,
        onLeftAction: @escaping @MainActor (LeftKeyAction) -> Void,
        onPresetReps: @escaping @MainActor (_ weightKg: Double?, _ reps: Int) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) {
        self.field = field
        self.setType = setType
        self.exercise = exercise
        self.recentWeightKg = recentWeightKg
        self.onKeyPress = onKeyPress
        self.onLeftAction = onLeftAction
        self.onPresetReps = onPresetReps
        self.onDone = onDone

        // Build content view with wrappers that also emit the standard input
        // click. Wrapping the closures keeps the audio feedback contract local
        // to this view (Stage 3 doesn't have to remember to call it).
        let clickingKeyPress: @MainActor (NumericKeypadKey) -> Void = { key in
            UIDevice.current.playInputClick()
            onKeyPress(key)
        }
        let clickingLeft: @MainActor (LeftKeyAction) -> Void = { action in
            UIDevice.current.playInputClick()
            onLeftAction(action)
        }
        let clickingPreset: @MainActor (Double?, Int) -> Void = { weight, reps in
            UIDevice.current.playInputClick()
            onPresetReps(weight, reps)
        }
        let clickingDone: @MainActor () -> Void = {
            UIDevice.current.playInputClick()
            onDone()
        }

        let content = WorkoutNumericKeyboardContentView(
            field: field,
            setType: setType,
            exercise: exercise,
            recentWeightKg: recentWeightKg,
            theme: Self.resolveTheme(isDark: UITraitCollection.current.userInterfaceStyle == .dark),
            onKeyPress: clickingKeyPress,
            onLeftAction: clickingLeft,
            onPresetReps: clickingPreset,
            onDone: clickingDone
        )
        self.host = UIHostingController(rootView: content)
        super.init(frame: .zero)

        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    private func setUp() {
        backgroundColor = .systemGroupedBackground
        translatesAutoresizingMaskIntoConstraints = false

        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let height = Self.preferredHeight()
        let constraint = heightAnchor.constraint(equalToConstant: height)
        constraint.priority = .required
        constraint.isActive = true
        heightConstraint = constraint

        // Ensure the content view's theme matches this view's own trait
        // collection (may differ from the class-level `UITraitCollection.current`
        // sampled at init time, e.g. when the host presents in a scene whose
        // interface style overrides the app default).
        refreshTheme()
    }

    // MARK: Trait / colorScheme bridging

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            refreshTheme()
        }
    }

    /// Rebuild `host.rootView` with a theme resolved from the current trait
    /// collection. The content view is a value type; replacing `rootView` is
    /// the SwiftUI way to push a fresh environment value into the hosted tree.
    private func refreshTheme() {
        let existing = host.rootView
        let theme = Self.resolveTheme(isDark: currentIsDark())
        guard theme.isDark != existing.theme.isDark ||
              theme.seed != existing.theme.seed ||
              theme.neutral != existing.theme.neutral else {
            return
        }
        host.rootView = WorkoutNumericKeyboardContentView(
            field: existing.field,
            setType: existing.setType,
            exercise: existing.exercise,
            recentWeightKg: existing.recentWeightKg,
            theme: theme,
            onKeyPress: existing.onKeyPress,
            onLeftAction: existing.onLeftAction,
            onPresetReps: existing.onPresetReps,
            onDone: existing.onDone
        )
    }

    // MARK: Public API — updating context between key presses

    /// Update the keyboard context. Consumers call this when the focused
    /// field or its surrounding state changes (e.g. user tabs from weight to
    /// reps in the same row). Cheap: only re-renders the SwiftUI content.
    func update(
        field: SetField,
        setType: SetType,
        exercise: Exercise?,
        recentWeightKg: Double?
    ) {
        self.field = field
        self.setType = setType
        self.exercise = exercise
        self.recentWeightKg = recentWeightKg

        // Re-hydrate the hosting root view with the new context. The closures
        // are stable — reuse the audio-click wrappers by copying the existing
        // root's callbacks. Theme is also re-resolved from the current trait
        // collection so any pending light/dark change is picked up here.
        let existing = host.rootView
        host.rootView = WorkoutNumericKeyboardContentView(
            field: field,
            setType: setType,
            exercise: exercise,
            recentWeightKg: recentWeightKg,
            theme: Self.resolveTheme(isDark: currentIsDark()),
            onKeyPress: existing.onKeyPress,
            onLeftAction: existing.onLeftAction,
            onPresetReps: existing.onPresetReps,
            onDone: existing.onDone
        )

        let newHeight = Self.preferredHeight()
        if heightConstraint?.constant != newHeight {
            heightConstraint?.constant = newHeight
        }
    }

    // MARK: Height policy

    /// Preferred height per spec: iPad ≤ 280pt / iPhone ≤ 260pt.
    static func preferredHeight() -> CGFloat {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        return isPad ? 260 : 240
    }
}

// MARK: - SwiftUI Preview

#Preview("Weight — working set") {
    WorkoutNumericKeyboardContentView(
        field: .weight,
        setType: .working,
        exercise: nil,
        recentWeightKg: 40,
        theme: Theme(seed: .teal, neutral: .slate, isDark: false),
        onKeyPress: { _ in },
        onLeftAction: { _ in },
        onPresetReps: { _, _ in },
        onDone: {}
    )
    .frame(height: 240)
}

#Preview("Reps — warmup (function keys disabled)") {
    WorkoutNumericKeyboardContentView(
        field: .reps,
        setType: .warmup,
        exercise: nil,
        recentWeightKg: nil,
        theme: Theme(seed: .teal, neutral: .slate, isDark: false),
        onKeyPress: { _ in },
        onLeftAction: { _ in },
        onPresetReps: { _, _ in },
        onDone: {}
    )
    .frame(height: 240)
}

#endif
