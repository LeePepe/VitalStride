// swiftlint:disable no_hardcoded_chinese
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
    case decreaseWeightFive
    case decreaseWeightTwoPointFive
    case increaseWeightTwoPointFive
    case increaseWeightFive
    case addPyramidSet
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
    @State private var selectionFeedbackTrigger = 0

    static let doneButtonBackgroundUIColor = UIColor.tintColor
    static let doneButtonForegroundUIColor = UIColor { traits in
        let background = UIColor.tintColor.resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard background.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .black }

        func linearized(_ value: CGFloat) -> Double {
            let component = Double(value)
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        let luminance = 0.2126 * linearized(red) + 0.7152 * linearized(green) + 0.0722 * linearized(blue)
        let whiteContrast = 1.05 / (luminance + 0.05)
        let blackContrast = (luminance + 0.05) / 0.05
        return whiteContrast >= blackContrast ? .white : .black
    }

    static func weightUnitToggleTitle() -> String {
        String(localized: "workout.keyboard.weight_unit", defaultValue: "kg / lb", comment: "Toggle between kilogram and pound display units")
    }

    static func repsPresetTitle(_ reps: Int) -> String {
        switch reps {
        case 5: return String(localized: "workout.keyboard.reps_5", defaultValue: "5 reps", comment: "Repetition preset")
        case 8: return String(localized: "workout.keyboard.reps_8", defaultValue: "8 reps", comment: "Repetition preset")
        case 10: return String(localized: "workout.keyboard.reps_10", defaultValue: "10 reps", comment: "Repetition preset")
        case 12: return String(localized: "workout.keyboard.reps_12", defaultValue: "12 reps", comment: "Repetition preset")
        default: return String(localized: "workout.keyboard.reps_15", defaultValue: "15 reps", comment: "Repetition preset")
        }
    }

    init(
        field: SetField,
        setType: SetType,
        exercise: Exercise?,
        recentWeightKg: Double?,
        suggestedWeightKg: Double? = nil,
        suggestedReps: Int? = nil,
        theme: Theme = Theme(seed: .teal, neutral: .slate),
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

    private var hasAISuggestion: Bool {
        suggestedWeightKg != nil && suggestedReps != nil
    }

    var body: some View {
        VStack(spacing: 8) {
            accessoryValueBar
                .frame(minHeight: 44)
            accessoryAttributeBar
                .frame(minHeight: 44)
            HStack(spacing: 8) {
                NumericKeypad(mode: field.isDecimalEnabled ? .decimal : .integer, onKeyPress: onKeyPress)
                    .frame(maxWidth: .infinity)
                doneKey(height: NumericKeypad.totalGridHeight)
                    .frame(width: 76)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground).ignoresSafeArea(.all, edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5) }
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
    }

    @ViewBuilder
    private var accessoryValueBar: some View {
        HStack(spacing: 6) {
            if field.isWeightField {
                accessoryPill("−5", action: .decreaseWeightFive)
                accessoryPill("−2.5", action: .decreaseWeightTwoPointFive)
                accessoryPill("+2.5", action: .increaseWeightTwoPointFive)
                accessoryPill("+5", action: .increaseWeightFive)
                accessoryPill(Self.weightUnitToggleTitle(), action: .toggleWeightUnit)
            } else {
                ForEach([5, 8, 10, 12, 15], id: \.self) { reps in
                    Button(Self.repsPresetTitle(reps)) { selectionFeedbackTrigger += 1; onPresetReps(recentWeightKg, reps) }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }

    private var accessoryAttributeBar: some View {
        HStack(spacing: 6) {
            accessoryPill(setType == .warmup ? String(localized: "workout.keyboard.warmup", defaultValue: "Warm-up", comment: "Toggle warm-up set") : String(localized: "workout.keyboard.working", defaultValue: "Working", comment: "Toggle working set"), action: .setWarmup, active: setType == .warmup)
            accessoryPill(String(localized: "workout.keyboard.laterality", defaultValue: "Single / Both", comment: "Toggle unilateral mode"), action: .toggleUnilateral)
            accessoryPill(String(localized: "workout.keyboard.add_drop", defaultValue: "+ Drop", comment: "Add drop set"), action: .addDropSet)
            accessoryPill(String(localized: "workout.keyboard.add_pyramid", defaultValue: "+ Pyramid", comment: "Add pyramid set"), action: .addPyramidSet)
            accessoryPill(String(localized: "workout.keyboard.copy_short", defaultValue: "Copy", comment: "Copy to next set"), action: .copyToNext)
        }
    }

    private func accessoryPill(_ title: String, action: LeftKeyAction, active: Bool = false) -> some View {
        Button(title) { selectionFeedbackTrigger += 1; onLeftAction(action) }
            .font(.caption.weight(active ? .semibold : .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(active ? Color.accentColor : Color(uiColor: .label))
            .background((active ? Color.orange.opacity(0.18) : Color(uiColor: .secondarySystemFill)), in: Capsule())
            .buttonStyle(KeyboardKeyButtonStyle())
            .accessibilityAddTraits(.isKeyboardKey)
    }



    private func doneKey(height: CGFloat) -> some View {
        Button {
            selectionFeedbackTrigger += 1
            onDone()
        } label: {
            Text(String(localized: "workout_keyboard.done_label", defaultValue: "Done", comment: "Dismiss workout keyboard"))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .foregroundStyle(Color(uiColor: Self.doneButtonForegroundUIColor))
                .background(
                    Color.accentColor,
                    in: RoundedRectangle(cornerRadius: NumericKeypad.keyRadius, style: .continuous)
                )
        }
        .buttonStyle(KeyboardKeyButtonStyle())
        .accessibilityIdentifier("workout_keyboard_done")
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

    // Retained for source compatibility with existing snapshot helpers. The
    // keyboard's production styling uses semantic system colors instead.
    static func resolveTheme(isDark: Bool) -> Theme {
        Theme(seed: .teal, neutral: .slate, isDark: isDark)
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
            onKeyPress: clickingKeyPress,
            onLeftAction: clickingLeft,
            onPresetReps: clickingPreset,
            onDone: clickingDone
        )
        self.host = UIHostingController(rootView: content)
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
        backgroundColor = .secondarySystemBackground

        // A detached inputView owns its full bounds; do not import screen safe-area
        // insets into its fixed keyboard height a second time.
        host.safeAreaRegions = []
        host.view.backgroundColor = .secondarySystemBackground
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
        bottomOverhangView.backgroundColor = .secondarySystemBackground
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
        let background = UIColor.secondarySystemBackground
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
        let background = UIColor.secondarySystemBackground
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
        // root's callbacks. Semantic system colors adapt automatically to the
        // hosting view's current trait collection.
        let existing = host.rootView
        host.rootView = WorkoutNumericKeyboardContentView(
            field: field,
            setType: setType,
            exercise: exercise,
            recentWeightKg: recentWeightKg,
            suggestedWeightKg: suggestedWeightKg,
            suggestedReps: suggestedReps,
            theme: existing.theme,
            onKeyPress: existing.onKeyPress,
            onLeftAction: existing.onLeftAction,
            onPresetReps: existing.onPresetReps,
            onDone: existing.onDone
        )
        let background = UIColor.secondarySystemBackground
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
    private static let iPhonePreferredHeight: CGFloat = NumericKeypad.totalGridHeight + 44 + 44 + 8 + 8 + 16
    private static let iPadPreferredHeight: CGFloat = iPhonePreferredHeight + 20

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
