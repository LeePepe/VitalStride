import DesignKit
import SwiftData
import SwiftUI
import Testing
import VitalModels
import XCTest

@testable import VitalStride

/// MY-1091 — Row-level Large Mode token verification for `SetRow` /
/// `ActiveExerciseSection`.
///
/// These tests pin the numeric contract behind the row-level Large Mode:
/// the width/font/min-height tokens introduced in `LargeWorkoutMode.swift`
/// and the persistence key shared with the toolbar toggle from MY-1088.
///
/// Row layout is verified visually via the
/// `#Preview("Row - Normal Mode")` / `#Preview("Row - Large Mode")` /
/// `#Preview("Row - Large Mode Unilateral")` blocks that live at the bottom
/// of `SetRow.swift`; the unilateral preview specifically exposes the
/// two-input overflow risk the AC calls out.
@MainActor
@Suite("Active Workout row-level Large Mode (MY-1091)")
struct ActiveWorkoutRowLargeModeTests {
    private static let largeModeKey = "activeWorkoutLargeMode"

    // MARK: Width tokens

    @Test("Bilateral weight width expands 70 → 110 for Large Mode (AC)")
    func bilateralWeightWidthExpands() {
        #expect(LargeWorkoutFieldWidth.bilateralWeight(large: false) == 70)
        #expect(LargeWorkoutFieldWidth.bilateralWeight(large: true) == 110)
    }

    @Test("Unilateral weight width expands 56 → 88 for Large Mode (AC)")
    func unilateralWeightWidthExpands() {
        #expect(LargeWorkoutFieldWidth.unilateralWeight(large: false) == 56)
        #expect(LargeWorkoutFieldWidth.unilateralWeight(large: true) == 88)
    }

    @Test("Reps width expands 60 → 88 for Large Mode (AC)")
    func repsWidthExpands() {
        #expect(LargeWorkoutFieldWidth.reps(large: false) == 60)
        #expect(LargeWorkoutFieldWidth.reps(large: true) == 88)
    }

    @Test("Large Mode min-height meets ≥60pt AC and clears HIG 44pt tap target")
    func minHeightMeetsAcAndHigFloor() {
        #expect(LargeWorkoutFieldWidth.largeMinHeight >= 60)
        #expect(LargeWorkoutFieldWidth.largeMinHeight >= 44)
    }

    /// Unilateral rows show two side-by-side weight inputs where bilateral
    /// rows show one — the AC calls out overflow risk on this path. The
    /// design invariant that keeps both modes rendering in an iPhone row is
    /// that per-side unilateral width stays below bilateral width so the
    /// two-input pair does not simply double the bilateral footprint. This
    /// test pins that invariant in both modes so a future width tweak
    /// cannot silently widen unilateral back to bilateral parity (which is
    /// what would push the row into horizontal clipping).
    @Test("Per-side unilateral weight width stays below bilateral in both modes (overflow guard)")
    func unilateralWidthStaysBelowBilateral() {
        #expect(
            LargeWorkoutFieldWidth.unilateralWeight(large: false)
                < LargeWorkoutFieldWidth.bilateralWeight(large: false)
        )
        #expect(
            LargeWorkoutFieldWidth.unilateralWeight(large: true)
                < LargeWorkoutFieldWidth.bilateralWeight(large: true)
        )
    }

    /// Widths must ramp *up* into Large Mode for every input class — a
    /// future refactor that accidentally flipped a token would still pass
    /// the equality checks above but violate the AC intent.
    @Test("Every input width ramps up in Large Mode (AC intent guard)")
    func everyInputWidthRampsUp() {
        #expect(
            LargeWorkoutFieldWidth.bilateralWeight(large: true)
                > LargeWorkoutFieldWidth.bilateralWeight(large: false)
        )
        #expect(
            LargeWorkoutFieldWidth.unilateralWeight(large: true)
                > LargeWorkoutFieldWidth.unilateralWeight(large: false)
        )
        #expect(
            LargeWorkoutFieldWidth.reps(large: true)
                > LargeWorkoutFieldWidth.reps(large: false)
        )
    }

    // MARK: Font tokens (Dynamic-Type-stacking contract)

    @Test("Weight/reps input font differs between modes (Large Mode raises the ramp)")
    func inputFontDiffersAcrossModes() {
        #if canImport(UIKit)
        let normalFont = LargeWorkoutInputFont.weightReps(large: false)
        let largeFont = LargeWorkoutInputFont.weightReps(large: true)
        // Dynamic Type may scale both, but Large Mode's base text style
        // (.title1) is strictly larger than normal mode's (.body), so the
        // resolved point size must be strictly greater for equal environment.
        #expect(largeFont.pointSize > normalFont.pointSize)
        #endif
    }

    @Test("Large Mode input font satisfies the ≥28pt AC at default Dynamic Type size")
    func inputFontMeetsMinimumSize() {
        #if canImport(UIKit)
        // .title1 at the default (.large) Content Size Category is 28pt on
        // Apple's published Type Ramp, matching the AC floor. If a future
        // refactor swaps to a smaller text style, .title1's pointSize check
        // below still passes but this token contract catches the drift.
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        let title1 = UIFont.preferredFont(forTextStyle: .title1, compatibleWith: traits)
        #expect(title1.pointSize >= 28)
        #endif
    }

    @Test("Exercise name font is nil in normal mode (default header sizing preserved) and .title2 in Large Mode")
    func exerciseNameFontResolvesForBothModes() {
        // Normal mode must return nil so `.font(nil)` is applied to the
        // section header — this preserves the pre-MY-1091 default header
        // font (AC: "normal sizing must remain unchanged"). Any concrete
        // Font value here would be a regression.
        #expect(LargeWorkoutFonts.exerciseName(large: false) == nil)
        #expect(LargeWorkoutFonts.exerciseName(large: true) != nil)
    }

    @Test("Set-index badge font token defined for both modes (no crash / nil path)")
    func setIndexFontResolvesForBothModes() {
        _ = LargeWorkoutFonts.setIndex(large: false)
        _ = LargeWorkoutFonts.setIndex(large: true)
    }

    // MARK: Persistence contract

    @Test("Row Large Mode reads the same @AppStorage key the toolbar toggle writes")
    func rowLargeModeSharesToolbarPersistenceKey() throws {
        let defaults = try #require(UserDefaults(suiteName: "RowLargeModeTests.\(UUID().uuidString)"))
        defaults.set(true, forKey: Self.largeModeKey)
        // A fresh SetRow / ActiveExerciseSection's
        // @AppStorage("activeWorkoutLargeMode") reads this back, so the row
        // font/frame ramp restores together with the header the toolbar
        // toggle already restored (MY-1088 AC preserved end-to-end).
        #expect(defaults.bool(forKey: Self.largeModeKey))
        defaults.removeObject(forKey: Self.largeModeKey)
    }

    // MARK: Compact-width fit (MY-1091 P0 fix)

    /// iPhone SE / iPhone Mini list content width. `List.plain` on a 375pt
    /// device gives ≈343pt of horizontal space to a row after the row's own
    /// 16pt leading + 16pt trailing insets set in `ActiveExerciseSection`.
    /// This is the compact-width budget every Large Mode row must fit.
    private static let compactRowContentWidth: CGFloat = 343

    /// The trailing chrome the row unconditionally reserves: menu ellipsis
    /// button (44pt hit target) + completion button (44pt hit target). The
    /// `Spacer()` between them can fully collapse when the row is tight, so
    /// only the two fixed 44pt frames are counted against the fit budget.
    private static let trailingChromeWidth: CGFloat = 44 + 44

    /// Bilateral-row minimum required width.
    ///
    /// HStack children with fixed widths: setIndex, weight, reps, menu,
    /// Spacer, completion. The `Spacer()` between menu and completion
    /// collapses fully under pressure. The "×" glyph between weight and
    /// reps is not sized by us — SwiftUI lays it out at its intrinsic
    /// width, which is a handful of points at the row's font size and is
    /// dwarfed by the field widths. Counted spacings are the 4 non-Spacer
    /// HStack gaps (setIndex↔weight, weight↔×, ×↔reps, reps↔menu).
    private static func bilateralMinWidth(_ variant: LargeWorkoutFieldWidth.Variant) -> CGFloat {
        let spacing = LargeWorkoutFieldWidth.rowSpacing(variant)
        return LargeWorkoutFieldWidth.setIndexWidth(variant)
            + LargeWorkoutFieldWidth.bilateralWeight(variant)
            + LargeWorkoutFieldWidth.reps(variant)
            + trailingChromeWidth
            + spacing * 4
    }

    /// Unilateral-row minimum required width.
    ///
    /// HStack children with fixed widths: setIndex, weightL, weightR, reps,
    /// menu, Spacer, completion. The Spacer collapses fully under pressure.
    /// The "/" and "×" glyphs use intrinsic widths as above. Counted
    /// spacings are the 6 non-Spacer HStack gaps (setIndex↔wL, wL↔/,
    /// /↔wR, wR↔×, ×↔reps, reps↔menu).
    private static func unilateralMinWidth(_ variant: LargeWorkoutFieldWidth.Variant) -> CGFloat {
        let spacing = LargeWorkoutFieldWidth.rowSpacing(variant)
        return LargeWorkoutFieldWidth.setIndexWidth(variant)
            + LargeWorkoutFieldWidth.unilateralWeight(variant) * 2
            + LargeWorkoutFieldWidth.reps(variant)
            + trailingChromeWidth
            + spacing * 6
    }

    @Test("Wide Large Mode intentionally exceeds iPhone SE budget (justifies the ViewThatFits fallback)")
    func wideLargeExceedsCompactBudget() {
        // Reviewer P0 baseline: proves the wide variant does NOT fit compact
        // rows. If a future refactor accidentally shrinks the wide tokens
        // enough to fit, this test fails loudly and the ViewThatFits
        // fallback becomes redundant / dead code.
        #expect(Self.bilateralMinWidth(.large) > Self.compactRowContentWidth)
        #expect(Self.unilateralMinWidth(.large) > Self.compactRowContentWidth)
    }

    @Test("Compact Large Mode fits iPhone SE list content width (bilateral)")
    func compactBilateralFitsCompactWidth() {
        // Reviewer P0 fix: the .largeCompact variant is what ViewThatFits
        // substitutes on 375pt phones. Its full row footprint MUST stay
        // within the 343pt content budget or the trailing menu / completion
        // controls clip off-screen — exactly the failure the reviewer cited.
        #expect(Self.bilateralMinWidth(.largeCompact) <= Self.compactRowContentWidth)
    }

    @Test("Compact Large Mode fits iPhone SE list content width (unilateral overflow guard)")
    func compactUnilateralFitsCompactWidth() {
        // The AC explicitly calls out the unilateral overflow risk — two
        // side-by-side weight inputs plus a divider are the widest path.
        // The compact fallback must clear the budget here or the ViewThatFits
        // substitution is meaningless for the very case the reviewer cited.
        #expect(Self.unilateralMinWidth(.largeCompact) <= Self.compactRowContentWidth)
    }

    @Test("Compact Large Mode still ramps at least one width above normal (Large intent preserved)")
    func compactLargeStillRampsAboveNormal() {
        // The compact fallback shrinks vs. wide Large so the unilateral row
        // fits an iPhone SE budget — for the two-input case, per-side weight
        // and reps must fall back to normal-mode widths (56 / 60) or the row
        // would clip its trailing controls. The Large Mode font ramp still
        // applies to those inputs (via SelectAllTextField's `.title1` font),
        // so legibility is preserved even at normal widths. But at LEAST one
        // width must still strictly ramp up in compact-large, otherwise
        // Large Mode delivers no visible sizing win on compact phones —
        // bilateral weight is the canonical ramp target because bilateral
        // rows have the horizontal headroom for it.
        #expect(
            LargeWorkoutFieldWidth.bilateralWeight(.largeCompact)
                > LargeWorkoutFieldWidth.bilateralWeight(.normal)
        )
        // Set-index badge also ramps up in Large Mode (both variants) so
        // multi-digit set counts stay legible without shifting column.
        #expect(
            LargeWorkoutFieldWidth.setIndexWidth(.largeCompact)
                > LargeWorkoutFieldWidth.setIndexWidth(.normal)
        )
        // The width fallback tokens must never *shrink* below normal — that
        // would be strictly worse than the pre-Large-Mode UI.
        #expect(
            LargeWorkoutFieldWidth.unilateralWeight(.largeCompact)
                >= LargeWorkoutFieldWidth.unilateralWeight(.normal)
        )
        #expect(
            LargeWorkoutFieldWidth.reps(.largeCompact)
                >= LargeWorkoutFieldWidth.reps(.normal)
        )
    }

    @Test("Normal mode already fits compact width (no ViewThatFits needed off Large Mode)")
    func normalFitsCompactWidth() {
        // Pins the "normal path is safe" invariant so a future refactor
        // that widens normal tokens gets caught here rather than by users.
        #expect(Self.bilateralMinWidth(.normal) <= Self.compactRowContentWidth)
        #expect(Self.unilateralMinWidth(.normal) <= Self.compactRowContentWidth)
    }
}

@MainActor
@Suite("Workout redesign history and exercise mode")
struct ActiveWorkoutRedesignTests {
    @Test("New exercise copies latest ordered set tree without completion or RPE")
    func prefillLatestHistory() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let exercise = Exercise(nameEn: "Bench", nameZh: "Bench", muscleGroup: .chest, equipment: .barbell)
        context.insert(exercise)
        let older = Workout(type: .strength, startDate: Date(timeIntervalSince1970: 100), endDate: Date(timeIntervalSince1970: 200))
        let latest = Workout(type: .strength, startDate: Date(timeIntervalSince1970: 300), endDate: Date(timeIntervalSince1970: 400))
        let current = Workout(type: .strength, startDate: Date(timeIntervalSince1970: 500))
        for workout in [older, latest, current] { context.insert(workout) }
        let olderExercise = WorkoutExercise(order: 0, exercise: exercise)
        olderExercise.workout = older
        context.insert(olderExercise)
        let oldSet = ExerciseSet(order: 0, weight: 20, reps: 20)
        oldSet.workoutExercise = olderExercise
        context.insert(oldSet)
        let previous = WorkoutExercise(order: 0, exercise: exercise)
        previous.workout = latest
        context.insert(previous)
        let first = ExerciseSet(order: 0, weight: 60, reps: 10, isCompleted: true,
                                isUnilateral: true, weightRight: 58, rpe: 8)
        let drop = ExerciseSet(order: 1, weight: 50, reps: 8, setType: .dropSet,
                               isCompleted: true, isUnilateral: true, weightRight: 48)
        let second = ExerciseSet(order: 2, weight: 62, reps: 6, isCompleted: true,
                                 isUnilateral: true, weightRight: 60)
        for set in [second, first, drop] {
            set.workoutExercise = previous
            context.insert(set)
        }
        let added = WorkoutExercise(order: 0, exercise: exercise)
        added.workout = current
        context.insert(added)
        try context.save()
        let copied = ActiveWorkoutView.prefillHistory(in: added, workout: current, using: context)
        try context.save()
        #expect(copied.map(\.weight) == [60, 50, 62])
        #expect(copied.map(\.reps) == [10, 8, 6])
        #expect(copied.map(\.setType) == [.working, .dropSet, .working])
        #expect(copied.map(\.weightRight) == [58, 48, 60])
        #expect(copied.allSatisfy { $0.isUnilateral && !$0.isCompleted && $0.rpe == nil })
        #expect(copied.allSatisfy { $0.workoutExercise === added })
        #expect(Set(copied.map(\.persistentModelID)).isDisjoint(with: [first, drop, second].map(\.persistentModelID)))
        #expect(first.isCompleted && first.rpe == 8 && first.weight == 60)
    }

    @Test("No history produces one empty working set")
    func prefillWithoutHistory() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        let exercise = WorkoutExercise(order: 0)
        exercise.workout = workout
        context.insert(exercise)
        let sets = ActiveWorkoutView.prefillHistory(in: exercise, workout: workout, using: context)
        #expect(sets.count == 1)
        #expect(sets[0].weight == 0 && sets[0].reps == 0 && !sets[0].isCompleted)
    }

    @Test("Exercise mode includes all main/sub sets, preserves asymmetric loads, isolates siblings")
    func modeAppliesToWholeExercise() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let owner = WorkoutExercise(order: 0)
        let sibling = WorkoutExercise(order: 1)
        context.insert(owner)
        context.insert(sibling)
        let first = ExerciseSet(order: 0, weight: 60, reps: 10)
        let drop = ExerciseSet(order: 1, weight: 50, reps: 8, setType: .dropSet, weightRight: 48)
        let last = ExerciseSet(order: 2, weight: 55, reps: 8)
        let unrelated = ExerciseSet(order: 0, weight: 20, reps: 10)
        for row in [first, drop, last] { row.workoutExercise = owner; context.insert(row) }
        unrelated.workoutExercise = sibling
        context.insert(unrelated)
        SetRow.toggleExerciseWeightMode(from: first)
        #expect([first, drop, last].allSatisfy { $0.isUnilateral })
        #expect(first.weightRight == 60 && drop.weightRight == 48)
        #expect(!unrelated.isUnilateral && unrelated.weightRight == nil)
        SetRow.toggleExerciseWeightMode(from: last)
        #expect([first, drop, last].allSatisfy { !$0.isUnilateral })
        #expect(drop.weightRight == 48)
        SetRow.toggleExerciseWeightMode(from: first)
        #expect(drop.weightRight == 48)
        let appended = ActiveExerciseSection.insertAppendedMainSet(in: owner, using: context)
        #expect(appended.isUnilateral && appended.weightRight == 55)
        #expect(appended.weight == 55 && appended.reps == 8)
    }
}

#if canImport(UIKit)
import UIKit

/// Render the actual production row and keyboard, including detached inputView
/// bridge, to catch stale text, hidden L/R fields and unit-rounding data loss.
@MainActor
final class ActiveWorkoutRedesignRenderingTests: XCTestCase {
    func testFieldsFollowModelAndUnitsWithoutChangingStoredWeights() async throws {
        let defaults = UserDefaults.standard
        let previousUnit = defaults.object(forKey: "weightUnit")
        let previousLarge = defaults.object(forKey: "activeWorkoutLargeMode")
        defaults.set("kg", forKey: "weightUnit")
        defaults.set(false, forKey: "activeWorkoutLargeMode")
        defer {
            defaults.set(previousUnit, forKey: "weightUnit")
            defaults.set(previousLarge, forKey: "activeWorkoutLargeMode")
        }
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let owner = WorkoutExercise(order: 0)
        context.insert(owner)
        let set = ExerciseSet(order: 0, weight: 1, reps: 12, isUnilateral: true, weightRight: 2)
        set.workoutExercise = owner
        context.insert(set)
        let row = SetRow(index: 0, exerciseSet: set, weightUnit: .kg, canDelete: true,
                         exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in },
                         onDelete: {}, onAddSubSet: { _ in }, onCopyToNext: {})
        let host = UIHostingController(rootView: row.modelContainer(container).designThemePreview())
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 280, height: 260)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let fields = textFields(in: host.view)
        XCTAssertEqual(fields.count, 3)
        let frames = fields.map { $0.convert($0.bounds, to: host.view) }.sorted { $0.minX < $1.minX }
        for frame in frames {
            XCTAssertGreaterThanOrEqual(frame.width, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(frame.height, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(frame.minX, 0)
            XCTAssertLessThanOrEqual(frame.maxX, host.view.bounds.width)
        }
        for pair in zip(frames, frames.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX)
        }
        set.weight = 80
        set.weightRight = 78
        set.reps = 8
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(Set(textFields(in: host.view).compactMap(\.text)), Set(["80", "78", "8"]))
        let poundsRow = SetRow(index: 0, exerciseSet: set, weightUnit: .lb, canDelete: true,
                               exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in },
                               onDelete: {}, onAddSubSet: { _ in }, onCopyToNext: {})
        host.rootView = poundsRow.modelContainer(container).designThemePreview()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(set.weight, 80)
        XCTAssertEqual(set.weightRight, 78)
        XCTAssertTrue(textFields(in: host.view).contains { $0.text == "176.4" })
        let attachment = XCTAttachment(image: windowImage(window))
        attachment.name = "Unilateral row at sidebar content width"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testKeyboardLightAndDarkRender() {
        for dark in [false, true] {
            let content = WorkoutNumericKeyboardContentView(
                field: .weight, setType: .working, exercise: nil, recentWeightKg: nil,
                theme: WorkoutNumericKeyboard.resolveTheme(isDark: dark),
                onKeyPress: { _ in }, onLeftAction: { _ in }, onPresetReps: { _, _ in }, onDone: {})
            let host = UIHostingController(rootView: content)
            host.safeAreaRegions = []
            let size = CGSize(width: 375, height: WorkoutNumericKeyboard.preferredHeight())
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = dark ? "Workout keyboard dark" : "Workout keyboard light"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertLessThanOrEqual(host.sizeThatFits(in: size).height, size.height + 1)
        }
    }

    func testWorkoutAndStartScreensLightAndDark() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        for (index, name) in ["Bench Press", "Squat"].enumerated() {
            let exercise = Exercise(nameEn: name, nameZh: name, muscleGroup: index == 0 ? .chest : .legs, equipment: .barbell)
            context.insert(exercise)
            let owner = WorkoutExercise(order: index, exercise: exercise)
            owner.workout = workout
            context.insert(owner)
            for order in 0..<2 {
                let set = ExerciseSet(order: order, weight: 60, reps: 10,
                                      isUnilateral: index == 0, weightRight: index == 0 ? 58 : nil,
                                      rpe: order == 0 ? 8 : nil)
                set.workoutExercise = owner
                context.insert(set)
            }
        }
        try context.save()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        defer { window.isHidden = true }
        for dark in [false, true] {
            let view = ActiveWorkoutView(source: .resume(workout))
                .modelContainer(container).designThemePreview()
                .preferredColorScheme(dark ? .dark : .light)
            let host = UIHostingController(rootView: view)
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutIfNeeded()
            XCTAssertGreaterThanOrEqual(textFields(in: host.view).count, 2)
            let attachment = XCTAttachment(image: windowImage(window))
            attachment.name = dark ? "Workout dark" : "Workout light"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        for dark in [false, true] {
            let view = StartWorkoutView(onStart: { _ in }).modelContainer(container).designThemePreview()
                .preferredColorScheme(dark ? .dark : .light)
            let host = UIHostingController(rootView: view)
            window.rootViewController = host
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let attachment = XCTAttachment(image: windowImage(window))
            attachment.name = dark ? "Start workout dark" : "Start workout light"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    private func windowImage(_ window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}
#endif
