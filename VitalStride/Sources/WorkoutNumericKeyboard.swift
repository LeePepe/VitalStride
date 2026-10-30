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
    /// Add a drop-set (descending) sub-set. Only enabled for `SetType.working`.
    case addDropSet
    /// Toggle between bilateral and unilateral weight entry.
    case toggleUnilateral
    /// Copy the current set's values to the next set.
    case copyToNext
    case setWarmup
    case addSet
    case toggleWeightUnit
    case applyAISuggestion
}

// MARK: - SwiftUI content view

#if canImport(UIKit) && !os(macOS)

/// SwiftUI content view rendered inside `WorkoutNumericKeyboard`.
///
/// One header with the only Done action, a central digit grid, and two
/// side columns for exercise/set shortcuts. UIKit retains the callback bridge.
struct WorkoutNumericKeyboardContentView: View {
    let field: SetField
    let setType: SetType
    let exercise: Exercise?
    let recentWeightKg: Double?
    let suggestedWeightKg: Double?
    let suggestedReps: Int?
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

    static func weightUnitToggleTitle() -> String {
        String(
            localized: "workout.keyboard.weight_unit",
            defaultValue: "kg / lb",
            comment: "Toggle between kilogram and pound display units"
        )
    }

    init(
        field: SetField,
        setType: SetType,
        exercise: Exercise?,
        recentWeightKg: Double?,
        suggestedWeightKg: Double? = nil,
        suggestedReps: Int? = nil,
        theme: Theme,
        onKeyPress: @escaping @MainActor (NumericKeypadKey) -> Void,
        onLeftAction: @escaping @MainActor (LeftKeyAction) -> Void,
        onPresetReps: @escaping @MainActor (_ weightKg: Double?, _ reps: Int) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) {
        self.field = field
        self.setType = setType
        self.exercise = exercise
        self.recentWeightKg = recentWeightKg
        self.suggestedWeightKg = suggestedWeightKg
        self.suggestedReps = suggestedReps
        self.theme = theme
        self.onKeyPress = onKeyPress
        self.onLeftAction = onLeftAction
        self.onPresetReps = onPresetReps
        self.onDone = onDone
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    functionKey(.toggleUnilateral, title: String(localized: "workout.keyboard.mode", defaultValue: "Total / L-R", comment: "Toggle the whole exercise weight mode"))
                    functionKey(.setWarmup, title: String(localized: "workout.keyboard.warmup", defaultValue: "Warmup", comment: "Set warmup type"))
                    functionKey(
                        .toggleWeightUnit,
                        title: Self.weightUnitToggleTitle()
                    )
                }
                .frame(width: 68, height: NumericKeypad.totalGridHeight)
                NumericKeypad(mode: field.isDecimalEnabled ? .decimal : .integer, onKeyPress: onKeyPress)
                    .layoutPriority(1)
                VStack(spacing: 8) {
                    functionKey(.addDropSet, title: String(localized: "workout.keyboard.drop", defaultValue: "Drop set", comment: "Add a drop set"))
                    functionKey(.addSet, title: String(localized: "workout.keyboard.add_set", defaultValue: "Add set", comment: "Add a set"))
                    if suggestedWeightKg != nil, suggestedReps != nil {
                        functionKey(
                            .applyAISuggestion,
                            title: String(
                                localized: "workout.keyboard.ai_suggest",
                                defaultValue: "✨ AI",
                                comment: "Apply AI smart progression suggestion"
                            )
                        )
                    }
                    Button(action: onDone) {
                        Text(String(localized: "workout_keyboard.done_label", defaultValue: "Done", comment: "Dismiss workout keyboard"))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                            .foregroundStyle(theme.onInteractiveAccent)
                            .background(theme.interactiveAccent, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout_keyboard_done")
                }
                .frame(width: 68, height: NumericKeypad.totalGridHeight)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            theme.neutrals.bg
                .ignoresSafeArea(.all, edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.neutrals.border)
                .frame(height: 1)
        }
        .environment(\.theme, theme)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
        .accessibilityElement(children: .contain)
    }

    private func functionKey(_ action: LeftKeyAction, title: String) -> some View {
        Button {
            onLeftAction(action)
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                .foregroundStyle(theme.accent)
                .background(theme.inner, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled((action == .addDropSet && setType.isSubSet) ||
                  (action == .applyAISuggestion && (suggestedWeightKg == nil || suggestedReps == nil)))
        .accessibilityIdentifier("workout_keyboard_" + action.rawValue)
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
    private var suggestedWeightKg: Double?
    private var suggestedReps: Int?
    private let onKeyPress: @MainActor (NumericKeypadKey) -> Void
    private let onLeftAction: @MainActor (LeftKeyAction) -> Void
    private let onPresetReps: @MainActor (_ weightKg: Double?, _ reps: Int) -> Void
    private let onDone: @MainActor () -> Void

    /// SwiftUI hosting controller — retained so its view stays anchored while
    /// the keyboard is on-screen.
    private let host: UIHostingController<WorkoutNumericKeyboardContentView>
    var hostingController: UIHostingController<WorkoutNumericKeyboardContentView>? { host }
    private let bottomOverhangView = UIView()

    /// Height constraint applied on install, including the 44pt header.
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
        suggestedWeightKg: Double? = nil,
        suggestedReps: Int? = nil,
        onKeyPress: @escaping @MainActor (NumericKeypadKey) -> Void,
        onLeftAction: @escaping @MainActor (LeftKeyAction) -> Void,
        onPresetReps: @escaping @MainActor (_ weightKg: Double?, _ reps: Int) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) {
        self.field = field
        self.setType = setType
        self.exercise = exercise
        self.recentWeightKg = recentWeightKg
        self.suggestedWeightKg = suggestedWeightKg
        self.suggestedReps = suggestedReps
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
            suggestedWeightKg: suggestedWeightKg,
            suggestedReps: suggestedReps,
            theme: Self.resolveTheme(isDark: UITraitCollection.current.userInterfaceStyle == .dark),
            onKeyPress: clickingKeyPress,
            onLeftAction: clickingLeft,
            onPresetReps: clickingPreset,
            onDone: clickingDone
        )
        self.host = UIHostingController(rootView: content)
        self.host.overrideUserInterfaceStyle = content.theme.isDark ? .dark : .light
        super.init(frame: .zero)

        setUp()
    }

    override convenience init(frame: CGRect) {
        self.init(
            field: .weight,
            setType: .working,
            exercise: nil,
            recentWeightKg: nil,
            onKeyPress: { _ in },
            onLeftAction: { _ in },
            onPresetReps: { _, _ in },
            onDone: {}
        )
        self.frame = frame
        setNeedsLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    private func setUp() {
        clipsToBounds = false
        isOpaque = true
        translatesAutoresizingMaskIntoConstraints = false
        let initialTheme = Self.resolveTheme(isDark: currentIsDark())
        backgroundColor = UIColor(initialTheme.neutrals.bg)

        // A detached inputView owns its full bounds; do not import screen safe-area
        // insets into its fixed keyboard height a second time.
        host.safeAreaRegions = []
        host.view.backgroundColor = UIColor(initialTheme.neutrals.bg)
        host.view.isOpaque = true
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.view.topAnchor.constraint(equalTo: topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        bottomOverhangView.translatesAutoresizingMaskIntoConstraints = false
        bottomOverhangView.isUserInteractionEnabled = false
        bottomOverhangView.isOpaque = true
        bottomOverhangView.backgroundColor = UIColor(initialTheme.neutrals.bg)
        addSubview(bottomOverhangView)
        NSLayoutConstraint.activate([
            bottomOverhangView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomOverhangView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomOverhangView.topAnchor.constraint(equalTo: bottomAnchor),
            bottomOverhangView.heightAnchor.constraint(equalToConstant: 64)
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
        if theme.isDark != existing.theme.isDark ||
           theme.seed != existing.theme.seed ||
           theme.neutral != existing.theme.neutral {
            host.rootView = WorkoutNumericKeyboardContentView(
                field: existing.field,
                setType: existing.setType,
                exercise: existing.exercise,
                recentWeightKg: existing.recentWeightKg,
                suggestedWeightKg: existing.suggestedWeightKg,
                suggestedReps: existing.suggestedReps,
                theme: theme,
                onKeyPress: existing.onKeyPress,
                onLeftAction: existing.onLeftAction,
                onPresetReps: existing.onPresetReps,
                onDone: existing.onDone
            )
            host.overrideUserInterfaceStyle = theme.isDark ? .dark : .light
        }
        let background = UIColor(theme.neutrals.bg)
        backgroundColor = background
        host.view.backgroundColor = background
        bottomOverhangView.backgroundColor = background
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshTheme()
        layoutSubviews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let background = UIColor(Self.resolveTheme(isDark: currentIsDark()).neutrals.bg)
        backgroundColor = background
        host.view.backgroundColor = background
        bottomOverhangView.backgroundColor = background
    }

    // MARK: Public API — updating context between key presses

    /// Update the keyboard context. Consumers call this when the focused
    /// field or its surrounding state changes (e.g. user tabs from weight to
    /// reps in the same row). Cheap: only re-renders the SwiftUI content.
    func update(
        field: SetField,
        setType: SetType,
        exercise: Exercise?,
        recentWeightKg: Double?,
        suggestedWeightKg: Double? = nil,
        suggestedReps: Int? = nil
    ) {
        self.field = field
        self.setType = setType
        self.exercise = exercise
        self.recentWeightKg = recentWeightKg
        self.suggestedWeightKg = suggestedWeightKg
        self.suggestedReps = suggestedReps

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
            suggestedWeightKg: suggestedWeightKg,
            suggestedReps: suggestedReps,
            theme: Self.resolveTheme(isDark: currentIsDark()),
            onKeyPress: existing.onKeyPress,
            onLeftAction: existing.onLeftAction,
            onPresetReps: existing.onPresetReps,
            onDone: existing.onDone
        )
        host.overrideUserInterfaceStyle = currentIsDark() ? .dark : .light

        let background = UIColor(Self.resolveTheme(isDark: currentIsDark()).neutrals.bg)
        backgroundColor = background
        host.view.backgroundColor = background
        bottomOverhangView.backgroundColor = background

        let newHeight = Self.preferredHeight()
        if heightConstraint?.constant != newHeight {
            heightConstraint?.constant = newHeight
        }
    }

    // MARK: Height policy

    /// Compact three-column layout with no separate header row.
    private static let iPhonePreferredHeight: CGFloat = 280
    private static let iPadPreferredHeight: CGFloat = 300

    static func preferredHeight() -> CGFloat {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        return isPad ? iPadPreferredHeight : iPhonePreferredHeight
    }
}

// MARK: - SwiftUI Preview

#Preview("Weight — working set") {
    WorkoutNumericKeyboardContentView(
        field: .weight,
        setType: .working,
        exercise: nil,
        recentWeightKg: 40,
        suggestedWeightKg: nil,
        suggestedReps: nil,
        theme: Theme(seed: .teal, neutral: .slate, isDark: false),
        onKeyPress: { _ in },
        onLeftAction: { _ in },
        onPresetReps: { _, _ in },
        onDone: {}
    )
    .frame(height: 300)
}

#Preview("Reps — warmup (function keys disabled)") {
    WorkoutNumericKeyboardContentView(
        field: .reps,
        setType: .warmup,
        exercise: nil,
        recentWeightKg: nil,
        suggestedWeightKg: nil,
        suggestedReps: nil,
        theme: Theme(seed: .teal, neutral: .slate, isDark: false),
        onKeyPress: { _ in },
        onLeftAction: { _ in },
        onPresetReps: { _, _ in },
        onDone: {}
    )
    .frame(height: 300)
}

#endif
