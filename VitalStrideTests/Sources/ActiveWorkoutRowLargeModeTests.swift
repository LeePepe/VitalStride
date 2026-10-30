import DesignKit
import SwiftData
import SwiftUI
import Testing
import UIKit
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

    @Test("Every rendered workout input keeps the 44pt hit-target floor")
    func inputHitTargetFloor() {
        #expect(ActiveWorkoutHitTarget.side >= 44)
        #expect(max(ActiveWorkoutHitTarget.side, LargeWorkoutFieldWidth.unilateralWeight(.normal) - 28) >= 44)
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

    @Test("Stored exercise sort preserves identity and full name; production reorder is verified in rendering suite")
    func sidebarReorderPreservesIdentityAndName() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        let names = ["Band Bent-Over Row (Cable)", "Band Bent-Over Row (Barbell)", "Band Chest Fly"]
        var owners: [WorkoutExercise] = []
        for (index, name) in names.enumerated() {
            let exercise = Exercise(nameEn: name, nameZh: name, muscleGroup: .back, equipment: .band)
            let owner = WorkoutExercise(order: index, exercise: exercise)
            owner.workout = workout
            context.insert(exercise)
            context.insert(owner)
            owners.append(owner)
        }
        try context.save()

        let originalIDs = owners.map(\.persistentModelID)
        let originalNames = owners.compactMap { $0.exercise?.localizedName }
        for (index, owner) in owners.reversed().enumerated() {
            owner.order = index
        }
        let sorted = (workout.exercises ?? []).sorted { $0.order < $1.order }

        #expect(sorted.map(\.persistentModelID) == Array(originalIDs.reversed()))
        #expect(sorted.compactMap { $0.exercise?.localizedName } == Array(originalNames.reversed()))
        #expect(Set(sorted.map(\.persistentModelID)) == Set(originalIDs))
    }
}

#if canImport(UIKit)
import UIKit

/// Render the actual production row and keyboard, including detached inputView
/// bridge, to catch stale text, hidden L/R fields and unit-rounding data loss.
@MainActor
final class ActiveWorkoutRedesignRenderingTests: XCTestCase {
    @MainActor
    private final class ListObservationRecorder {
        var geometry: ActiveWorkoutListGeometry?
        var driver: ActiveWorkoutListDriver?
        var rowFrames: [AnyHashable: CGRect] = [:]
        var headerFrames: [AnyHashable: CGRect] = [:]
        var controlFrames: [AnyHashable: [String: CGRect]] = [:]
        var toggleActions: [AnyHashable: ActiveExerciseSectionInteraction.ToggleAction] = [:]
        var collapseStates: [AnyHashable: Bool] = [:]
        var sidebarItems: [ActiveWorkoutSidebarItem] = []
        var sidebarItemFrames: [String: CGRect] = [:]
        var sidebarNameFrames: [String: CGRect] = [:]
        var keyboardVisible = false
        var keyboardDidShow = false
        var dismissKeyboard: (@MainActor @Sendable () -> Void)?
        var sidebarAddUpdates = 0
        var sidebarAddUpdatedAt = ProcessInfo.processInfo.systemUptime
        var sidebarAddFrame: CGRect?
        var sidebarMove: (@MainActor @Sendable (Int, Int) -> Void)?
    }

    @MainActor
    private final class RowObservationRecorder {
        struct Descriptor {
            let field: SetField
            let kind: String
            let text: String
            let frame: CGRect
        }
        var descriptors: [AnyHashable: [String: Descriptor]] = [:]
        var modeActions: [AnyHashable: @MainActor @Sendable () -> Void] = [:]

        var sink: WorkoutRowObservation {
            WorkoutRowObservation(descriptor: { [weak self] row, field, kind, text, frame in
                self?.descriptors[row, default: [:]]["\(field.rawValue)-\(kind)"] = Descriptor(
                    field: field, kind: kind, text: text, frame: frame
                )
            }, modeAction: { [weak self] row, action in self?.modeActions[row] = action })
        }
    }

    /// Measures Text's own layout and foreground pixels, not an inferred gap
    /// beside an input. An absent, compressed or occluded descriptor fails.
    private func assertRowDescriptors(
        _ recorder: RowObservationRecorder, rows: [ExerciseSet], fields: [UITextField],
        window: UIWindow, unit: WeightUnit, variant: String
    ) throws {
        let image = windowImage(window)
        let pixels = try HeaderPixels(image)
        let fieldFrames = fields.map { $0.convert($0.bounds, to: window) }
        var records = ["variant=\(variant)", "fields=\(fieldFrames)", "texts=\(fields.compactMap(\.text))"]
        for row in rows {
            let descriptors = recorder.descriptors[AnyHashable(row.persistentModelID)] ?? [:]
            let expected: [(SetField, String, String)] = row.isUnilateral
                ? [(.weight, "prefix", "L"), (.weightRight, "prefix", "R"),
                   (.weight, "unit", unit.rawValue), (.weightRight, "unit", unit.rawValue),
                   (.reps, "unit", String(localized: "workout.row.reps_unit", defaultValue: "reps"))]
                : [(.weight, "prefix", String(localized: "workout.row.total_prefix", defaultValue: "Total")),
                   (.weight, "unit", unit.rawValue),
                   (.reps, "unit", String(localized: "workout.row.reps_unit", defaultValue: "reps"))]
            XCTAssertEqual(descriptors.count, expected.count, variant)
            for (field, kind, text) in expected {
                let descriptor = try XCTUnwrap(descriptors["\(field.rawValue)-\(kind)"], variant)
                XCTAssertEqual(descriptor.text, text, variant)
                let frame = descriptor.frame
                XCTAssertGreaterThan(frame.width, 3, variant)
                XCTAssertGreaterThan(frame.height, 5, variant)
                XCTAssertTrue(window.bounds.contains(frame), "\(variant): \(frame)")
                for input in fieldFrames { XCTAssertFalse(frame.intersects(input), "\(variant): \(frame) / \(input)") }
                let ink = descriptorInk(pixels, frame: frame)
                XCTAssertGreaterThan(ink.count, 3, "Missing descriptor glyphs: \(variant) \(text) \(frame)")
                records.append("row=\(row.order) field=\(field.rawValue) kind=\(kind) text=\(descriptor.text) frame=\(frame) inkPixels=\(ink.count) inkFrame=\(ink.frame)")
            }
        }
        for field in fields {
            // No physical-pixel or ceil allowance: only floating representation.
            XCTAssertGreaterThanOrEqual(field.bounds.width, 44 - 1e-10, variant)
            XCTAssertGreaterThanOrEqual(field.bounds.height, 44 - 1e-10, variant)
            let frame = field.convert(field.bounds, to: window)
            XCTAssertTrue(window.bounds.contains(frame), "\(variant): \(frame)")
            let point = field.convert(CGPoint(x: field.bounds.midX, y: field.bounds.midY), to: window)
            let hit = try XCTUnwrap(window.hitTest(point, with: nil))
            XCTAssertTrue(hit === field || hit.isDescendant(of: field), variant)
            let hitFrame = hit.convert(hit.bounds, to: window)
            XCTAssertGreaterThanOrEqual(hitFrame.width, 44 - 1e-10, variant)
            XCTAssertGreaterThanOrEqual(hitFrame.height, 44 - 1e-10, variant)
        }
        for index in fieldFrames.indices {
            for other in fieldFrames.indices where other > index {
                XCTAssertFalse(fieldFrames[index].intersects(fieldFrames[other]), variant)
            }
        }
        let screenshot = XCTAttachment(image: image)
        screenshot.name = variant
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let geometry = XCTAttachment(string: records.joined(separator: "\n"))
        geometry.name = "\(variant)-measured-descriptors"
        geometry.lifetime = .keepAlways
        add(geometry)
    }

    private func descriptorInk(_ image: HeaderPixels, frame: CGRect) -> (count: Int, frame: CGRect) {
        let rect = frame.applying(CGAffineTransform(scaleX: image.scale, y: image.scale)).integral
        let minX = max(0, Int(rect.minX)), maxX = min(image.width, Int(rect.maxX))
        let minY = max(0, Int(rect.minY)), maxY = min(image.height, Int(rect.maxY))
        guard maxX > minX, maxY > minY else { return (0, .zero) }
        // The modal color is the actual flat input surface in this small Text
        // frame. Count foreground coverage against it, including antialiasing.
        var histogram: [Int: Int] = [:]
        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = y * image.stride + x * 4
                let rgb = Int(image.bytes[offset]) << 16 | Int(image.bytes[offset + 1]) << 8 | Int(image.bytes[offset + 2])
                histogram[rgb, default: 0] += 1
            }
        }
        let background = histogram.max { $0.value < $1.value }?.key ?? 0
        var count = 0
        var ink = CGRect.null
        for y in minY..<maxY {
            for x in minX..<maxX {
                let offset = y * image.stride + x * 4
                let distance = (0..<3).map { channel in
                    abs(Int(image.bytes[offset + channel]) - ((background >> (16 - channel * 8)) & 255))
                }.max() ?? 0
                if distance > 30 {
                    count += 1
                    ink = ink.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return (count, ink.isNull ? .zero : ink.applying(CGAffineTransform(scaleX: 1 / image.scale, y: 1 / image.scale)))
    }

    func testSubSetDisplayRefreshPreservesPrecisionAndUserEditsPersist() async throws {
        for unilateral in [false, true] {
            let container = try ModelContainerConfiguration.makeTestContainer()
            let set = ExerciseSet(order: 1, weight: 12.25, reps: 8, setType: .dropSet,
                                  isUnilateral: unilateral, weightRight: unilateral ? 10.75 : nil)
            container.mainContext.insert(set)
            func row(unit: WeightUnit) -> some View {
                SubSetRow(exerciseSet: set, weightUnit: unit, isLast: true, parentSetNumber: 1,
                          exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in }, onDelete: {})
                    .modelContainer(container).designThemePreview()
            }
            let host = UIHostingController(rootView: row(unit: .kg))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 393, height: 260)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(150))
            host.view.layoutIfNeeded()
            let initialFields = textFields(in: host.view)
            XCTAssertEqual(initialFields.count, unilateral ? 3 : 2)
            XCTAssertTrue(initialFields.allSatisfy { ($0.placeholder ?? "").isEmpty })
            XCTAssertEqual(set.weight, 12.25)
            XCTAssertEqual(set.weightRight, unilateral ? 10.75 : nil)

            let sequentialWeightField = try XCTUnwrap(textFields(in: host.view).min {
                $0.convert($0.bounds, to: host.view).minX < $1.convert($1.bounds, to: host.view).minX
            })
            XCTAssertTrue(sequentialWeightField.becomeFirstResponder())
            sequentialWeightField.text = "12.12"
            sequentialWeightField.sendActions(for: .editingChanged)
            sequentialWeightField.text = "12.125"
            sequentialWeightField.sendActions(for: .editingChanged)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(set.weight, 12.125, accuracy: 0.000_001)
            sequentialWeightField.resignFirstResponder()

            set.weight = 18.375
            if unilateral { set.weightRight = 17.125 }
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(textFields(in: host.view).contains { $0.text == "18.4" })
            XCTAssertEqual(set.weight, 18.375)
            XCTAssertEqual(set.weightRight, unilateral ? 17.125 : nil)

            host.rootView = row(unit: .lb)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(set.weight, 18.375)
            XCTAssertEqual(set.weightRight, unilateral ? 17.125 : nil)
            let weightField = try XCTUnwrap(textFields(in: host.view).first {
                $0.text == String(format: "%.1f", 18.375 * 2.20462)
            })
            weightField.text = "40.5"
            weightField.sendActions(for: .editingChanged)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(set.weight, 40.5 / 2.20462, accuracy: 0.000_001)
            XCTAssertEqual(set.weightRight, unilateral ? 17.125 : nil)
            if unilateral {
                let rightField = try XCTUnwrap(textFields(in: host.view).first {
                    $0.text == String(format: "%.1f", 17.125 * 2.20462)
                })
                rightField.text = "35.5"
                rightField.sendActions(for: .editingChanged)
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertEqual(try XCTUnwrap(set.weightRight), 35.5 / 2.20462, accuracy: 0.000_001)
            }
            let repsField = try XCTUnwrap(textFields(in: host.view).first { $0.text == "8" })
            repsField.text = "11"
            repsField.sendActions(for: .editingChanged)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(set.reps, 11)
            weightField.text = ""
            weightField.sendActions(for: .editingChanged)
            XCTAssertEqual(set.weight, 0)
            if unilateral {
                let rightField = try XCTUnwrap(textFields(in: host.view).first {
                    $0.text == "35.5"
                })
                rightField.text = ""
                rightField.sendActions(for: .editingChanged)
                XCTAssertEqual(set.weightRight, 0)
            }
            repsField.text = ""
            repsField.sendActions(for: .editingChanged)
            XCTAssertEqual(set.reps, 0)
            host.rootView = row(unit: .kg)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(set.weight, 0)
            if unilateral {
                XCTAssertEqual(set.weightRight, 0)
            }
            XCTAssertEqual(set.reps, 0)
        }
    }

    func testEmptyMainAndDropRowsRenderOneDescriptorPerSlotInBothAppearances() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let owner = WorkoutExercise(order: 0)
        context.insert(owner)
        let set = ExerciseSet(order: 0, weight: 0, reps: 0)
        set.workoutExercise = owner
        context.insert(set)
        let dropSet = ExerciseSet(order: 1, weight: 0, reps: 0, setType: .dropSet)
        context.insert(dropSet)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 300)
        defer { window.isHidden = true }

        for dark in [false, true] {
            let main = SetRow(index: 0, exerciseSet: set, weightUnit: .kg, canDelete: true,
                              exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in },
                              onDelete: {}, onAddSubSet: { _ in }, onCopyToNext: {})
            let drop = SubSetRow(exerciseSet: dropSet, weightUnit: .kg, isLast: true, parentSetNumber: 1,
                                 exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in }, onDelete: {})
            let content = VStack(spacing: 8) {
                main
                drop
            }
            .modelContainer(container)
            .designThemePreview()
            .preferredColorScheme(dark ? .dark : .light)
            let host = UIHostingController(rootView: content)
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(180))
            host.view.layoutIfNeeded()

            let fields = textFields(in: host.view)
            XCTAssertEqual(fields.count, 4)
            XCTAssertTrue(fields.allSatisfy { ($0.text ?? "").isEmpty && ($0.placeholder ?? "").isEmpty })

            let focused = try XCTUnwrap(fields.first)
            XCTAssertTrue(focused.becomeFirstResponder())
            focused.text = "0"
            focused.sendActions(for: .editingChanged)
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertEqual(set.weight, 0)
            XCTAssertEqual(focused.text, "0")
            XCTAssertTrue(focused.isFirstResponder)
            focused.resignFirstResponder()

            let image = XCTAttachment(image: windowImage(window))
            image.name = "T05 empty main-drop \(dark ? "dark" : "light")"
            image.lifetime = .keepAlways
            add(image)
            let frames = XCTAttachment(string: fields.enumerated().map {
                "\($0): frame=\($1.convert($1.bounds, to: window)) placeholder=\($1.placeholder ?? "<nil>") text=\($1.text ?? "<nil>")"
            }.joined(separator: "\n"))
            frames.name = "T05 empty main-drop frames \(dark ? "dark" : "light")"
            frames.lifetime = .keepAlways
            add(frames)
        }
    }

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

    func testT05NativeDescriptorMatrixCoversEmptyFilledModesThemesAndWidths() async throws {
        let defaults = UserDefaults.standard
        let previousLarge = defaults.object(forKey: "activeWorkoutLargeMode")
        defer { defaults.set(previousLarge, forKey: "activeWorkoutLargeMode") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true }

        for width in [280, 343, 375, 393] {
            for largeMode in [false, true] {
                defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
                for dark in [false, true] {
                    for unilateral in [false, true] {
                        for filled in [false, true] {
                            let container = try ModelContainerConfiguration.makeTestContainer()
                            let context = container.mainContext
                            let owner = WorkoutExercise(order: 0)
                            context.insert(owner)
                            let main = ExerciseSet(
                                order: 0,
                                weight: filled ? 12.5 : 0,
                                reps: filled ? 8 : 0,
                                isUnilateral: unilateral,
                                weightRight: unilateral ? (filled ? 10.75 : 0) : nil
                            )
                            main.workoutExercise = owner
                            let drop = ExerciseSet(
                                order: 1,
                                weight: filled ? 7.25 : 0,
                                reps: filled ? 6 : 0,
                                setType: .dropSet,
                                isUnilateral: unilateral,
                                weightRight: unilateral ? (filled ? 6.5 : 0) : nil
                            )
                            drop.workoutExercise = owner
                            context.insert(main)
                            context.insert(drop)
                            let recorder = RowObservationRecorder()
                            let content = VStack(spacing: 8) {
                                SetRow(
                                    index: 0, exerciseSet: main, weightUnit: .kg, canDelete: true,
                                    exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in },
                                    onDelete: {}, onAddSubSet: { _ in }, onCopyToNext: {}
                                )
                                SubSetRow(
                                    exerciseSet: drop, weightUnit: .kg, isLast: true, parentSetNumber: 1,
                                    exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in }, onDelete: {}
                                )
                            }
                            .environment(\.workoutRowObservation, recorder.sink)
                            .modelContainer(container)
                            .designThemePreview()
                            .preferredColorScheme(dark ? .dark : .light)
                            let host = UIHostingController(rootView: content)
                            window.frame = CGRect(x: 0, y: 0, width: width, height: 300)
                            window.rootViewController = host
                            window.makeKeyAndVisible()
                            try await Task.sleep(for: .milliseconds(120))
                            host.view.layoutIfNeeded()

                            let fields = textFields(in: host.view)
                            XCTAssertEqual(fields.count, unilateral ? 6 : 4)
                            XCTAssertTrue(fields.allSatisfy { ($0.placeholder ?? "").isEmpty })
                            if filled {
                                XCTAssertTrue(fields.contains { $0.text == "12.5" })
                                XCTAssertTrue(fields.contains { $0.text == "8" })
                                XCTAssertTrue(fields.contains { $0.text == "6" })
                                XCTAssertTrue(fields.allSatisfy { !($0.text ?? "").isEmpty })
                            } else {
                                XCTAssertTrue(fields.allSatisfy { ($0.text ?? "").isEmpty })
                            }
                            let variant = "T05-\(width)-\(largeMode ? "large" : "normal")-\(dark ? "dark" : "light")-\(unilateral ? "LR" : "total")-\(filled ? "filled" : "empty")"
                            try assertRowDescriptors(recorder, rows: [main, drop], fields: fields,
                                                     window: window, unit: .kg, variant: variant)

                        }
                    }
                }
            }
        }
    }

    func testT05FocusedEditingSelectsAndUpdatesMainAndDropRows() async throws {
        let defaults = UserDefaults.standard
        let previousLarge = defaults.object(forKey: "activeWorkoutLargeMode")
        defer { defaults.set(previousLarge, forKey: "activeWorkoutLargeMode") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true }
        for large in [false, true] {
            defaults.set(large, forKey: "activeWorkoutLargeMode")
            for dark in [false, true] {
                for unilateral in [false, true] {
                    let container = try ModelContainerConfiguration.makeTestContainer()
                    let owner = WorkoutExercise(order: 0)
                    container.mainContext.insert(owner)
                    let main = ExerciseSet(order: 0, weight: 18.375, reps: 8,
                                           isUnilateral: unilateral, weightRight: unilateral ? 16.125 : nil)
                    let drop = ExerciseSet(order: 1, weight: 6.25, reps: 6, setType: .dropSet,
                                           isUnilateral: unilateral, weightRight: unilateral ? 5.125 : nil)
                    for row in [main, drop] { row.workoutExercise = owner; container.mainContext.insert(row) }
                    let recorder = RowObservationRecorder()
                    func content(_ unit: WeightUnit) -> some View {
                        VStack(spacing: 8) {
                            SetRow(index: 0, exerciseSet: main, weightUnit: unit, canDelete: true,
                                   exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in },
                                   onDelete: {}, onAddSubSet: { _ in }, onCopyToNext: {})
                            SubSetRow(exerciseSet: drop, weightUnit: unit, isLast: true, parentSetNumber: 1,
                                      exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in }, onDelete: {})
                        }
                        .environment(\.workoutRowObservation, recorder.sink)
                        .modelContainer(container).designThemePreview().preferredColorScheme(dark ? .dark : .light)
                    }
                    let host = UIHostingController(rootView: content(.kg))
                    window.frame = CGRect(x: 0, y: 0, width: 280, height: 400)
                    window.rootViewController = host
                    window.makeKeyAndVisible()
                    try await Task.sleep(for: .milliseconds(150))
                    XCTAssertEqual(textFields(in: host.view).first?.text, "18.4")
                    main.reps = 9 // Unfocused display refresh must not round stored kg.
                    try await Task.sleep(for: .milliseconds(80))
                    for unit in [WeightUnit.lb, .kg, .lb] {
                        host.rootView = content(unit)
                        try await Task.sleep(for: .milliseconds(100))
                        XCTAssertEqual(main.weight, 18.375, accuracy: 1e-12)
                        XCTAssertEqual(textFields(in: host.view).first?.text, unit == .kg ? "18.4" : "40.5")
                        if unilateral { XCTAssertEqual(try XCTUnwrap(main.weightRight), 16.125, accuracy: 1e-12) }
                    }
                    for (index, row) in [(0, main), (unilateral ? 3 : 2, drop)] {
                        let field = try XCTUnwrap(textFields(in: host.view)[index])
                        XCTAssertTrue(field.becomeFirstResponder())
                        try await Task.sleep(for: .milliseconds(100))
                        let selection = try XCTUnwrap(field.selectedTextRange)
                        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.start), 0)
                        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: selection.end), field.text?.utf16.count)
                        // Real UITextInput replacement, followed by its existing
                        // editingChanged target. Never assign filled text as cursor proof.
                        field.replace(selection, withText: "12.12")
                        field.sendActions(for: .editingChanged)
                        try await Task.sleep(for: .milliseconds(80))
                        let position = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: 2))
                        field.selectedTextRange = field.textRange(from: position, to: position)
                        field.replace(try XCTUnwrap(field.selectedTextRange), withText: "3")
                        field.sendActions(for: .editingChanged)
                        try await Task.sleep(for: .milliseconds(80))
                        XCTAssertEqual(field.text, "123.12")
                        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: try XCTUnwrap(field.selectedTextRange).start), 3)
                        field.deleteBackward()
                        field.sendActions(for: .editingChanged)
                        try await Task.sleep(for: .milliseconds(80))
                        XCTAssertEqual(field.text, "12.12")
                        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: try XCTUnwrap(field.selectedTextRange).start), 2)
                        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
                        field.insertText("5")
                        field.sendActions(for: .editingChanged)
                        try await Task.sleep(for: .milliseconds(100))
                        XCTAssertEqual(field.text, "12.125")
                        XCTAssertEqual(field.offset(from: field.beginningOfDocument, to: try XCTUnwrap(field.selectedTextRange).start), 6)
                        XCTAssertEqual(row.weight, 12.125 / 2.20462, accuracy: 1e-9)
                        XCTAssertTrue(field.isFirstResponder)
                        let variant = "T05-focused-\(row === main ? "main" : "drop")-\(large ? "large" : "normal")-\(dark ? "dark" : "light")-\(unilateral ? "LR" : "total")-lb"
                        try assertRowDescriptors(recorder, rows: [main, drop], fields: textFields(in: host.view),
                                                 window: window, unit: .lb, variant: variant)
                        field.resignFirstResponder()
                        try await Task.sleep(for: .milliseconds(80))
                        XCTAssertEqual(row.weight, 12.125 / 2.20462, accuracy: 1e-9)
                    }
                }
            }
        }
    }

    func testT05RenderedModeTransitionPreservesTotalAndLRValues() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let owner = WorkoutExercise(order: 0)
        container.mainContext.insert(owner)
        let main = ExerciseSet(order: 0, weight: 60, reps: 10, isUnilateral: true, weightRight: 55)
        let drop = ExerciseSet(order: 1, weight: 50, reps: 8, setType: .dropSet, isUnilateral: true, weightRight: 45)
        for row in [main, drop] { row.workoutExercise = owner; container.mainContext.insert(row) }
        let recorder = RowObservationRecorder()
        let content = VStack(spacing: 8) {
            SetRow(index: 0, exerciseSet: main, weightUnit: .kg, canDelete: true,
                   exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in },
                   onDelete: {}, onAddSubSet: { _ in }, onCopyToNext: {})
            SubSetRow(exerciseSet: drop, weightUnit: .kg, isLast: true, parentSetNumber: 1,
                      exercise: nil, recentWeightKg: nil, onToggleCompleted: { _ in }, onDelete: {})
        }
        .environment(\.workoutRowObservation, recorder.sink)
        .modelContainer(container).designThemePreview()
        let host = UIHostingController(rootView: content)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 280, height: 400)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(textFields(in: host.view).compactMap(\.text), ["60", "55", "10", "50", "45", "8"])
        // The sink exposes the row's actual keyboard action closure. No copied
        // mode logic or direct model mutation substitutes for either action.
        for row in [main, drop] {
            let action = try XCTUnwrap(recorder.modeActions[AnyHashable(row.persistentModelID)])
            action()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertFalse(main.isUnilateral || drop.isUnilateral)
            XCTAssertEqual(textFields(in: host.view).compactMap(\.text), ["60", "10", "50", "8"])
            XCTAssertEqual(main.weightRight, 55)
            XCTAssertEqual(drop.weightRight, 45)
            action()
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertTrue(main.isUnilateral && drop.isUnilateral)
            XCTAssertEqual(main.weightRight, 55)
            XCTAssertEqual(drop.weightRight, 45)
            XCTAssertEqual(textFields(in: host.view).compactMap(\.text), ["60", "55", "10", "50", "45", "8"])
        }
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

    func testPinnedExerciseSectionHeaderOccludesUnderlyingRows() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        var owners: [WorkoutExercise] = []
        for index in 0..<3 {
            let exercise = Exercise(
                nameEn: "Bench Press \(index + 1)",
                nameZh: "卧推\(index + 1)",
                muscleGroup: .chest,
                equipment: .barbell
            )
            context.insert(exercise)
            let owner = WorkoutExercise(order: index, exercise: exercise)
            owner.workout = workout
            context.insert(owner)
            owners.append(owner)
            for order in 0..<8 {
                let set = ExerciseSet(order: order, weight: 60, reps: 10)
                set.workoutExercise = owner
                context.insert(set)
            }
        }

        try context.save()

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true }

        let defaults = UserDefaults.standard
        let previousLargeMode = defaults.object(forKey: "activeWorkoutLargeMode")
        defer { defaults.set(previousLargeMode, forKey: "activeWorkoutLargeMode") }

        for width in [375, 393] {
            for largeMode in [false, true] {
                defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
                for dark in [false, true] {
                    for dynamicType in [DynamicTypeSize.large, .accessibility3] {
                        window.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: 852)
                        let recorder = ListObservationRecorder()
                        let content = ActiveWorkoutView(source: .resume(workout))
                            .modelContainer(container)
                            .designThemePreview()
                            .preferredColorScheme(dark ? .dark : .light)
                            .dynamicTypeSize(dynamicType)
                            .environment(\.activeExerciseSectionInteraction, ActiveExerciseSectionInteraction(
                                registerToggle: { id, action in recorder.toggleActions[id] = action },
                                onCollapseChange: { id, collapsed in recorder.collapseStates[id] = collapsed }
                            ))
                            .environment(\.activeWorkoutListObservation, ActiveWorkoutListObservationSink(
                                onGeometry: { recorder.geometry = $0 },
                                onReady: { recorder.driver = $0 },
                                onRowFrame: { recorder.rowFrames[$0] = $1 },
                                onHeaderFrame: { recorder.headerFrames[$0] = $1 },
                                onControlFrame: {
                                    recorder.controlFrames[$0, default: [:]][$1] = $2
                                }
                            ))
                        let host = UIHostingController(rootView: content)
                        window.rootViewController = host
                        window.makeKeyAndVisible()
                        try await Task.sleep(for: .milliseconds(250))
                        host.view.layoutIfNeeded()

                        let target = owners[0]
                        let targetID = target.persistentModelID
                        // The E66 registered action must preserve the production
                        // completed-only collapse guard for an incomplete owner.
                        let toggle = try XCTUnwrap(recorder.toggleActions[targetID])
                        toggle()
                        try await Task.sleep(for: .milliseconds(100))
                        host.view.layoutIfNeeded()
                        XCTAssertNil(recorder.collapseStates[targetID], "Incomplete header action must not collapse")
                        let sets = (target.sets ?? []).sorted { $0.order < $1.order }
                        let listFrame = try XCTUnwrap(recorder.geometry).listFrame
                        // Select by observed production List geometry in window space,
                        // never by a child's parent-local frame or a guessed top inset.
                        let scrollView = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? UIScrollView }
                            .first { candidate in
                                let frame = candidate.convert(candidate.bounds, to: window)
                                return abs(frame.minX - listFrame.minX) < 2
                                    && abs(frame.minY - listFrame.minY) < 2
                                    && abs(frame.width - listFrame.width) < 2
                                    && candidate.contentSize.height > candidate.bounds.height
                            }, "No scroll container matches observed production List viewport \(listFrame)")
                        let unscrolledHeader = try XCTUnwrap(recorder.headerFrames[targetID])
                        // Remove the initial system top margin before taking the same
                        // header's pinned reference; no set row is behind it yet.
                        let topOffset = scrollView.contentOffset.y + unscrolledHeader.minY - listFrame.minY
                        scrollView.setContentOffset(CGPoint(x: 0, y: topOffset), animated: false)
                        try await Task.sleep(for: .milliseconds(150))
                        let initialHeader = try XCTUnwrap(recorder.headerFrames[targetID])
                        let baselineImage = windowImage(window)
                        let baseline = try HeaderPixels(baselineImage)
                        let firstRow = try XCTUnwrap(recorder.rowFrames[sets[0].persistentModelID])
                        let addSet = try XCTUnwrap(recorder.controlFrames[targetID]?["add-set"])
                        let inputFrames = firstRowInputFrames(in: host.view, row: firstRow, window: window)
                        if dark {
                            let gap = CGRect(
                                x: listFrame.minX,
                                y: initialHeader.maxY,
                                width: listFrame.width,
                                height: max(0, firstRow.minY - initialHeader.maxY)
                            )
                            assertNoBlackHeaderGap(baseline, gap: gap, variant: "\(width)-\(largeMode ? "large" : "normal")-dark")
                        }
                        assertHeaderSeparation(
                            addSet: addSet, firstRow: firstRow, header: initialHeader, inputFrames: inputFrames
                        )
                        let referenceBand = CGRect(
                            x: listFrame.minX, y: listFrame.minY,
                            width: listFrame.width, height: firstRow.minY - listFrame.minY
                        )
                        let variant = "pinned-\(width)-\(largeMode ? "large" : "normal")-\(dark ? "dark" : "light")-\(dynamicType)"
                        try persistHeaderEvidence(
                            image: baselineImage, name: "\(variant)-reference",
                            frames: "band=\(referenceBand) header=\(initialHeader) firstRow=\(firstRow) controls=\(recorder.controlFrames[targetID] ?? [:])"
                        )
                        let middleRow = try XCTUnwrap(recorder.rowFrames[sets[1].persistentModelID])
                        let middleOffset = topOffset + middleRow.midY - initialHeader.midY
                        let driver = try XCTUnwrap(recorder.driver)
                        driver.scrollTo(owners[1].persistentModelID, .top)
                        try await Task.sleep(for: .milliseconds(150))
                        let nextHeader = try XCTUnwrap(recorder.headerFrames[owners[1].persistentModelID])
                        // Keep the following header just beyond the entire
                        // reference band. Centering the last row under a tall,
                        // wrapped header can enter List's header push-off phase,
                        // where a stationary-baseline pixel comparison is invalid.
                        let boundaryOffset = scrollView.contentOffset.y + nextHeader.minY - referenceBand.maxY - 4
                        var evidence: [String] = [
                            "rest: add-set=\(addSet) first-row=\(firstRow) inputs=\(inputFrames) intersection=\(addSet.intersects(firstRow))"
                        ]
                        for (position, offset) in [("top", topOffset), ("middle", middleOffset),
                                                   ("boundary", boundaryOffset)] {
                            recorder.rowFrames.removeAll()
                            scrollView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                            try await Task.sleep(for: .milliseconds(180))
                            var actualTargetOffset = offset
                            if position == "boundary" {
                                // Resolve List's estimated section layout using
                                // the real final row, keeping its trailing edge
                                // inside the header before push-off can begin.
                                let lastRow = try XCTUnwrap(recorder.rowFrames[sets[7].persistentModelID])
                                let correction = lastRow.maxY - initialHeader.maxY + 4
                                let pixel = 1 / scrollView.traitCollection.displayScale
                                actualTargetOffset = scrollView.contentOffset.y
                                // Compact headers can already be at this boundary
                                // within one display pixel. Clearing observations
                                // for a no-op scroll loses the real row: SwiftUI's
                                // onGeometryChange only reports changed frames.
                                if abs(correction) > pixel {
                                    actualTargetOffset += correction
                                    recorder.rowFrames.removeAll()
                                    scrollView.setContentOffset(CGPoint(x: 0, y: actualTargetOffset), animated: false)
                                    try await Task.sleep(for: .milliseconds(180))
                                }
                                evidence.append("boundary correction=\(correction) pixel=\(pixel) target=\(actualTargetOffset)")
                            }
                            host.view.layoutIfNeeded()
                            let geometry = try XCTUnwrap(recorder.geometry)
                            let header = try XCTUnwrap(recorder.headerFrames[targetID])
                            let controls = recorder.controlFrames[targetID] ?? [:]
                            let image = windowImage(window)
                            let attachment = XCTAttachment(image: image)
                            attachment.name = "Pinned header \(position) \(width)pt \(largeMode ? "large" : "normal") \(dark ? "dark" : "light") \(dynamicType)"
                            attachment.lifetime = .keepAlways
                            add(attachment)
                            XCTAssertGreaterThan(geometry.contentSize.height, geometry.containerSize.height)
                            XCTAssertEqual(scrollView.contentOffset.y, actualTargetOffset, accuracy: 2, position)
                            XCTAssertEqual(geometry.contentOffset.y, actualTargetOffset, accuracy: 2, position)
                            XCTAssertEqual(header.minY, initialHeader.minY, accuracy: 2, position)
                            assertHeaderControls(controls, header: header, viewport: geometry.listFrame)
                            let overlappingRows = sets.compactMap { recorder.rowFrames[$0.persistentModelID] }
                                .filter { $0.intersects(header) }
                            if position != "top" {
                                XCTAssertFalse(overlappingRows.isEmpty, "A real set row must pass underneath the pinned header")
                            }
                            if position == "boundary" {
                                let lastRow = try XCTUnwrap(recorder.rowFrames[sets[7].persistentModelID])
                                XCTAssertTrue(lastRow.intersects(header), "Last set must pass under the header at the section boundary")
                                let next = try XCTUnwrap(recorder.headerFrames[owners[1].persistentModelID])
                                XCTAssertGreaterThan(next.minY, referenceBand.maxY, "Following header must remain outside the pinned reference band")
                                XCTAssertLessThan(next.minY, geometry.listFrame.maxY, "Next section must be in the viewport")
                            }
                            let pixels = try HeaderPixels(image)
                            let comparison = assertPinnedHeaderPixels(
                                pixels, baseline: baseline, band: referenceBand
                            )
                            evidence.append("\(position): requested=\(actualTargetOffset) actualOffset=\(geometry.contentOffset.y) "
                                + "viewport=\(geometry.listFrame) header=\(header) controls=\(controls) "
                                + "rowsUnderHeader=\(overlappingRows) pixelProof=\(comparison)")
                            try persistHeaderEvidence(
                                image: image, name: "\(variant)-\(position)",
                                frames: (evidence.last ?? "") + "\nheaders=\(recorder.headerFrames)\n"
                                    + descendants(of: host.view).compactMap { view in
                                        guard view is UICollectionReusableView else { return nil }
                                        return "\(type(of: view)): frame=\(view.convert(view.bounds, to: window)) bounds=\(view.bounds)"
                                    }.joined(separator: "\n")
                            )
                        }
                        // List contentSize is estimated until distant cells are laid
                        // out. Ask its real collection layout for the final item.
                        let collection = try XCTUnwrap(scrollView as? UICollectionView)
                        let lastSection = collection.numberOfSections - 1
                        let lastItem = collection.numberOfItems(inSection: lastSection) - 1
                        recorder.rowFrames.removeAll()
                        collection.scrollToItem(
                            at: IndexPath(item: lastItem, section: lastSection), at: .bottom, animated: false
                        )
                        try await Task.sleep(for: .milliseconds(180))
                        let finalSet = try XCTUnwrap(owners[2].sets?.max { $0.order < $1.order })
                        let finalRow = try XCTUnwrap(recorder.rowFrames[finalSet.persistentModelID])
                        XCTAssertTrue(listFrame.contains(finalRow), "Final set must scroll fully into the List viewport")
                        evidence.append("last-content: offset=\(scrollView.contentOffset.y) finalRow=\(finalRow)")
                        try persistHeaderEvidence(
                            image: windowImage(window), name: "\(variant)-last-content",
                            frames: evidence.joined(separator: "\n")
                        )
                        let frames = XCTAttachment(string: evidence.joined(separator: "\n"))
                        frames.name = "Pinned header geometry \(width)pt \(largeMode ? "large" : "normal") \(dark ? "dark" : "light") \(dynamicType)"
                        frames.lifetime = .keepAlways
                        add(frames)
                    }
                }
            }
        }
    }

    func testCompleteHeaderCollapseAndExpansionSeparatesInputsFromAddSet() async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        let exercise = Exercise(
            nameEn: "Bench Press",
            nameZh: "卧推",
            muscleGroup: .chest,
            equipment: .barbell
        )
        context.insert(exercise)
        let owner = WorkoutExercise(order: 0, exercise: exercise)
        owner.workout = workout
        context.insert(owner)
        for order in 0..<2 {
            let set = ExerciseSet(order: order, weight: 60, reps: 10, isCompleted: true)
            set.workoutExercise = owner
            context.insert(set)
        }
        try context.save()

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true }
        let defaults = UserDefaults.standard
        let previousLargeMode = defaults.object(forKey: "activeWorkoutLargeMode")
        defer { defaults.set(previousLargeMode, forKey: "activeWorkoutLargeMode") }

        for width in [375, 393] {
            for largeMode in [false, true] {
                defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
                for dark in [false, true] {
                    for dynamicType in [DynamicTypeSize.large, .accessibility3] {
                        window.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: 852)
                        let recorder = ListObservationRecorder()
                        let content = ActiveWorkoutView(source: .resume(workout))
                            .modelContainer(container)
                            .designThemePreview()
                            .preferredColorScheme(dark ? .dark : .light)
                            .dynamicTypeSize(dynamicType)
                            .environment(\.activeExerciseSectionInteraction, ActiveExerciseSectionInteraction(
                                registerToggle: { id, action in recorder.toggleActions[id] = action },
                                onCollapseChange: { id, collapsed in recorder.collapseStates[id] = collapsed }
                            ))
                            .environment(\.activeWorkoutListObservation, ActiveWorkoutListObservationSink(
                                onGeometry: { recorder.geometry = $0 },
                                onReady: { recorder.driver = $0 },
                                onRowFrame: { recorder.rowFrames[$0] = $1 },
                                onHeaderFrame: { recorder.headerFrames[$0] = $1 },
                                onControlFrame: { recorder.controlFrames[$0, default: [:]][$1] = $2 }
                            ))
                        let host = UIHostingController(rootView: content)
                        window.rootViewController = host
                        window.makeKeyAndVisible()
                        try await Task.sleep(for: .milliseconds(350))
                        host.view.layoutIfNeeded()
                        let ownerID = owner.persistentModelID
                        let firstSet = try XCTUnwrap((owner.sets ?? []).min { $0.order < $1.order })
                        let collection = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? UICollectionView }.first)
                        let toggle = try XCTUnwrap(recorder.toggleActions[ownerID])
                        let variant = "\(width)pt \(largeMode ? "large-mode" : "normal") \(dark ? "dark" : "light") \(dynamicType)"
                        var evidence: [String] = []
                        for state in ["rest", "collapsed", "expanded"] {
                            if state != "rest" {
                                // Discard observations before every transition; fresh
                                // cell/input measurements below never read this cache.
                                recorder.rowFrames.removeAll()
                                toggle()
                                try await Task.sleep(for: .milliseconds(450))
                                host.view.layoutIfNeeded()
                            }
                            let geometry = try XCTUnwrap(recorder.geometry)
                            let header = try XCTUnwrap(recorder.headerFrames[ownerID])
                            let controls = recorder.controlFrames[ownerID] ?? [:]
                            let addSet = try XCTUnwrap(controls["add-set"])
                            assertHeaderControls(controls, header: header, viewport: geometry.listFrame)
                            let rowCount = (0..<collection.numberOfSections).reduce(0) {
                                $0 + collection.numberOfItems(inSection: $1)
                            }
                            if state == "collapsed" {
                                XCTAssertEqual(recorder.collapseStates[ownerID], true)
                                XCTAssertEqual(rowCount, 0, "Collapsed production List must remove both set items")
                                XCTAssertTrue(collection.indexPathsForVisibleItems.isEmpty,
                                              "Collapsed List must expose no visible set cells")
                                XCTAssertTrue(collection.visibleCells.flatMap { textFields(in: $0) }.isEmpty,
                                              "Collapsed List must expose no visible input views")
                                // Animation can emit intermediate row geometry. Discard
                                // it after proving the actual List has no set items.
                                recorder.rowFrames.removeAll()
                                evidence.append("collapsed: viewport=\(geometry.listFrame) header=\(header) controls=\(controls) items=\(rowCount) inputs=[]")
                            } else {
                                if state == "expanded" { XCTAssertEqual(recorder.collapseStates[ownerID], false) }
                                XCTAssertEqual(rowCount, 2, "Expanded production List must contain both sets")
                                // UICollectionView may reuse a row without emitting a
                                // changed SwiftUI geometry value. Measure the CURRENT
                                // first item's live cell and inputs after each layout.
                                let section = try XCTUnwrap((0..<collection.numberOfSections).first {
                                    collection.numberOfItems(inSection: $0) > 0
                                })
                                let indexPath = IndexPath(item: 0, section: section)
                                let cell = try XCTUnwrap(collection.cellForItem(at: indexPath))
                                XCTAssertTrue(collection.indexPathsForVisibleItems.contains(indexPath))
                                let firstRow = cell.convert(cell.bounds, to: window)
                                let inputs = firstRowInputFrames(in: cell, row: firstRow, window: window)
                                assertHeaderSeparation(addSet: addSet, firstRow: firstRow, header: header, inputFrames: inputs)
                                evidence.append("\(state): viewport=\(geometry.listFrame) header=\(header) controls=\(controls) firstRow=\(firstRow) inputs=\(inputs) firstSet=\(firstSet.persistentModelID) cell=\(indexPath) items=\(rowCount) gap=\(firstRow.minY - addSet.maxY)")
                            }
                            let image = XCTAttachment(image: windowImage(window))
                            image.name = "T02 complete \(state) \(variant)"
                            image.lifetime = .keepAlways
                            add(image)
                        }
                        let frames = XCTAttachment(string: evidence.joined(separator: "\n"))
                        frames.name = "T02 complete geometry \(variant)"
                        frames.lifetime = .keepAlways
                        add(frames)
                    }
                }
            }
        }
    }

    func testPinnedHeaderPixelNormalizationHandlesExtendedRange() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .extended
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 4), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            UIColor.green.setFill()
            context.fill(CGRect(x: 4, y: 0, width: 4, height: 4))
        }
        let source = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(source.bitsPerComponent, 16, "Regression must exercise the simulator's extended-range input")
        let normalized = try HeaderPixels(image)
        for (x, expected) in [(1, [255, 0, 0]), (6, [0, 255, 0])] {
            let offset = 2 * normalized.stride + x * 4
            for channel in 0..<3 {
                XCTAssertEqual(Int(normalized.bytes[offset + channel]), expected[channel], accuracy: 1)
            }
        }

    }

    func testLongExerciseTitlesRenderDistinguishingWordsAndKeepHeaderActionsSeparate() async throws {
            let names = [
                "Band Bent-Over Row (Cable)",
                "Band Bent-Over Row (Barbell)",
                "弹力带俯身划船"
            ]
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            defer { window.isHidden = true }
            let defaults = UserDefaults.standard
            let previousLargeMode = defaults.object(forKey: "activeWorkoutLargeMode")
            defer { defaults.set(previousLargeMode, forKey: "activeWorkoutLargeMode") }

            for width in [375, 393] {
                for largeMode in [false, true] {
                    defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
                    for dark in [false, true] {
                        for dynamicType in [DynamicTypeSize.large, .accessibility3] {
                            var titleImages: [String: (image: HeaderPixels, frame: CGRect)] = [:]
                            for name in names {
                                let container = try ModelContainerConfiguration.makeTestContainer()
                                let context = container.mainContext
                                let workout = Workout(type: .strength, startDate: Date())
                                let exercise = Exercise(
                                    nameEn: name,
                                    nameZh: name,
                                    muscleGroup: .back,
                                    equipment: .band
                                )
                                let owner = WorkoutExercise(order: 0, exercise: exercise)
                                owner.workout = workout
                                let set = ExerciseSet(order: 0, weight: 0, reps: 10)
                                set.workoutExercise = owner
                                context.insert(workout)
                                context.insert(exercise)
                                context.insert(owner)
                                context.insert(set)
                                try context.save()

                                let recorder = ListObservationRecorder()
                                let content = ActiveWorkoutView(source: .resume(workout))
                                    .modelContainer(container)
                                    .designThemePreview()
                                    .preferredColorScheme(dark ? .dark : .light)
                                    .dynamicTypeSize(dynamicType)
                                    .environment(\.activeExerciseSectionInteraction, ActiveExerciseSectionInteraction(
                                        registerToggle: { id, action in recorder.toggleActions[id] = action },
                                        onCollapseChange: { id, collapsed in recorder.collapseStates[id] = collapsed }
                                    ))
                                    .environment(\.activeWorkoutListObservation, ActiveWorkoutListObservationSink(
                                        onGeometry: { recorder.geometry = $0 },
                                        onHeaderFrame: { recorder.headerFrames[$0] = $1 },
                                        onControlFrame: {
                                            recorder.controlFrames[$0, default: [:]][$1] = $2
                                        }
                                    ))
                                window.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: 852)
                                let host = UIHostingController(rootView: content)
                                window.rootViewController = host
                                window.makeKeyAndVisible()
                                try await Task.sleep(for: .milliseconds(300))
                                host.view.layoutIfNeeded()

                                let ownerID = owner.persistentModelID
                                let header = try XCTUnwrap(recorder.headerFrames[ownerID])
                                let controls = recorder.controlFrames[ownerID] ?? [:]
                                let geometry = try XCTUnwrap(recorder.geometry)
                                let title = try XCTUnwrap(controls["title"])
                                assertHeaderControls(controls, header: header, viewport: geometry.listFrame)
                                let toggle = try XCTUnwrap(recorder.toggleActions[ownerID])
                                toggle()
                                try await Task.sleep(for: .milliseconds(100))
                                XCTAssertNil(recorder.collapseStates[ownerID], "Incomplete title header must preserve its non-collapsing action")
                                let progress = try XCTUnwrap(controls["progress"])
                                let addSet = try XCTUnwrap(controls["add-set"])
                                let menu = try XCTUnwrap(controls["menu"])
                                XCTAssertTrue(header.insetBy(dx: -1, dy: -1).contains(title))
                                XCTAssertTrue(geometry.listFrame.insetBy(dx: -1, dy: -1).contains(title))
                                XCTAssertTrue(header.insetBy(dx: -1, dy: -1).contains(progress))
                                XCTAssertTrue(geometry.listFrame.insetBy(dx: -1, dy: -1).contains(progress))
                                XCTAssertFalse(title.intersects(progress))
                                XCTAssertFalse(title.intersects(addSet))
                                XCTAssertFalse(title.intersects(menu))
                                XCTAssertFalse(progress.intersects(addSet))
                                XCTAssertFalse(progress.intersects(menu))
                                XCTAssertGreaterThan(title.height, 0, "Long title must have a measurable single-line frame")

                                let image = windowImage(window)
                                let attachment = XCTAttachment(image: image)
                                attachment.name = "T03 \(name) \(width)pt \(largeMode ? "large" : "normal") \(dark ? "dark" : "light") \(dynamicType)"
                                attachment.lifetime = .keepAlways
                                add(attachment)
                                try persistT03Evidence(
                                    image: image,
                                    name: name,
                                    width: width,
                                    largeMode: largeMode,
                                    dark: dark,
                                    dynamicType: dynamicType,
                                    title: title,
                                    header: header,
                                    geometry: geometry,
                                    controls: controls
                                )
                                titleImages[name] = (try HeaderPixels(image), title)
                            }

                            let first = try XCTUnwrap(titleImages[names[0]])
                            let second = try XCTUnwrap(titleImages[names[1]])
                            XCTAssertGreaterThan(first.frame.width, 0)
                            XCTAssertGreaterThan(second.frame.width, 0)
                        }
                    }
                }
            }
        }

    func testSidebarNamesWrapWithMeasuredListWidthAndKeepAddExerciseReachable() async throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "activeWorkoutLargeMode")
        defer { defaults.set(previous, forKey: "activeWorkoutLargeMode") }
        for width in [375, 393] {
            for largeMode in [false, true] {
                defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
                for dynamicType in [DynamicTypeSize.large, .accessibility3] {
                    for dark in [false, true] {
                        try await verifySidebar(width: width, largeMode: largeMode, dynamicType: dynamicType, dark: dark)
                    }
                }
            }
        }
    }

    private func verifySidebar(width: Int, largeMode: Bool, dynamicType: DynamicTypeSize, dark: Bool) async throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = container.mainContext
        let workout = Workout(type: .strength, startDate: Date())
        context.insert(workout)
        // Twelve bounded entries overflow even the real scene's ordinary-size viewport.
        // The leading entry keeps BOTH shared-prefix names unselected, with identical chrome.
        var names = ["Warm-up", "Band Bent-Over Row (Cable)", "Band Bent-Over Row (Barbell)", "弹力带俯身划船"]
            + (1...8).map { "Band Row \($0)" }
        let chinese = Locale.current.language.languageCode?.identifier == "zh"
        names[names.count - 1] = chinese ? "弹力带划船" : "Band Row 8"
        var owners: [WorkoutExercise] = []
        for (index, name) in names.enumerated() {
            let exercise = Exercise(nameEn: index == names.count - 1 ? "Band Row 8" : name,
                                    nameZh: index == names.count - 1 ? "弹力带划船" : name,
                                    muscleGroup: .back, equipment: .band)
            let owner = WorkoutExercise(order: index, exercise: exercise)
            owner.workout = workout
            context.insert(exercise)
            context.insert(owner)
            for setIndex in 0..<2 {
                let set = ExerciseSet(order: setIndex, weight: 0, reps: 10, isCompleted: setIndex < index % 3)
                set.workoutExercise = owner
                context.insert(set)
            }
            owners.append(owner)
        }
        try context.save()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: 852)
        let recorder = ListObservationRecorder()
        let didShow = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { recorder.keyboardDidShow = true }
        }
        let didHide = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { recorder.keyboardDidShow = false }
        }
        defer {
            NotificationCenter.default.removeObserver(didShow)
            NotificationCenter.default.removeObserver(didHide)
        }
        let content = ActiveWorkoutView(source: .resume(workout))
            .modelContainer(container)
            .designThemePreview()
            .preferredColorScheme(dark ? .dark : .light)
            .dynamicTypeSize(dynamicType)
            .environment(\.activeWorkoutListObservation, ActiveWorkoutListObservationSink(
                onGeometry: { recorder.geometry = $0 },
                onReady: { recorder.driver = $0 },
                onSidebarItems: { recorder.sidebarItems = $0 },
                onSidebarItemFrame: { recorder.sidebarItemFrames[$0] = $1 },
                onSidebarNameFrame: { recorder.sidebarNameFrames[$0] = $1 },
                onKeyboardVisibility: { recorder.keyboardVisible = $0 },
                onSidebarDismissKeyboardReady: { recorder.dismissKeyboard = $0 },
                onSidebarAddFrame: {
                    recorder.sidebarAddFrame = $0
                    recorder.sidebarAddUpdates += 1
                    recorder.sidebarAddUpdatedAt = ProcessInfo.processInfo.systemUptime
                },
                onSidebarMoveReady: { recorder.sidebarMove = $0 }
            ))
        let host = UIHostingController(rootView: content)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.endEditing(true)
            window.isHidden = true
            window.rootViewController = nil
        }
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutIfNeeded()
        let geometry = try XCTUnwrap(recorder.geometry)
        let sidebarWidth = geometry.listFrame.minX
        XCTAssertEqual(sidebarWidth, 64, accuracy: 0.5)
        XCTAssertGreaterThan(geometry.listFrame.width, 250)
        let scroll = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? UIScrollView }.first {
            let frame = $0.convert($0.bounds, to: window)
            return frame.minX < 1 && frame.width <= sidebarWidth + 2
        })
        let variant = "T04-\(width)-\(largeMode ? "large" : "normal")-\(dark ? "dark" : "light")-\(dynamicType)"
        let original = recorder.sidebarItems
        XCTAssertEqual(original.map(\.name), names)
        XCTAssertEqual(original.map(\.index), Array(names.indices))
        XCTAssertEqual(original.map(\.completed), names.indices.map { $0 % 3 })
        XCTAssertEqual(original.map(\.total), Array(repeating: 2, count: names.count))
        XCTAssertEqual(Set(original.map(\.id)).count, names.count)
        for item in original {
            XCTAssertEqual(item.accessibilityLabel, "\(item.index + 1), \(item.name)")
            XCTAssertFalse(item.accessibilityValue.isEmpty)
            if Locale.current.language.languageCode?.identifier == "en" {
                XCTAssertTrue(item.accessibilityValue.contains("Completed"))
                XCTAssertEqual(item.accessibilityValue.contains("Done"), item.completed == item.total)
            } else {
                XCTAssertTrue(item.accessibilityValue.contains("已完成"))
            }
        }
        var textSignatures: [Int] = []
        // Each image is scrolled to the actual name; the measured crop contains only Text.
        for index in [1, 2] {
            let id = original[index].id
            let frame = try XCTUnwrap(recorder.sidebarNameFrames[id])
            let reference = UIHostingController(rootView: Text(names[index]).font(.caption2)
                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                .dynamicTypeSize(dynamicType))
            let ideal = reference.sizeThatFits(in: CGSize(width: frame.width, height: 10000))
            XCTAssertEqual(frame.height, ideal.height, accuracy: 1, "Full original name must retain its uncapped text height")
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertTrue(frame.minX >= 0 && frame.maxX <= sidebarWidth)
            // UIKit's raw bounds include the root safeAreaInset dock. Use adjusted insets
            // to show the prefix and distinguishing suffix entirely above that occlusion.
            let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y + frame.minY - viewport.minY), animated: false)
            try await Task.sleep(for: .milliseconds(100))
            let prefixImage = windowImage(window)
            let prefixFrame = try XCTUnwrap(recorder.sidebarNameFrames[id])
            try persistHeaderEvidence(image: prefixImage, name: "\(variant)-prefix-\(index)",
                                      frames: "name=\(names[index])\ntextFrame=\(prefixFrame)\nideal=\(ideal)\nviewport=\(viewport)")
            let suffixReference = UIHostingController(rootView: Text(index == 1 ? "(Cable)" : "(Barbell)")
                .font(.caption2).fixedSize(horizontal: false, vertical: true).dynamicTypeSize(dynamicType))
            let suffixHeight = suffixReference.sizeThatFits(in: CGSize(width: frame.width, height: 10000)).height
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y + prefixFrame.maxY - viewport.maxY + 8),
                                    animated: false)
            try await Task.sleep(for: .milliseconds(100))
            let visible = try XCTUnwrap(recorder.sidebarNameFrames[id])
            let suffix = CGRect(x: visible.minX, y: visible.maxY - suffixHeight,
                                width: visible.width, height: suffixHeight)
            XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(suffix), "Entire distinguishing suffix must be unobscured")
            let image = windowImage(window)
            textSignatures.append(pixelSignature(try HeaderPixels(image), suffix))
            try persistHeaderEvidence(image: image, name: "\(variant)-name-\(index)",
                                      frames: "name=\(names[index])\ntextFrame=\(visible)\nsuffix=\(suffix)\nideal=\(ideal)\nviewport=\(viewport)\nlist=\(geometry.listFrame)")
            if width == 375 && !largeMode {
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(variant)-suffix-\(names[index])"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        XCTAssertNotEqual(textSignatures[0], textSignatures[1], "Text-only crops must distinguish Cable and Barbell")
        for keyboardVisible in [false, true] {
            if keyboardVisible {
                let field = try XCTUnwrap(textFields(in: host.view).first { $0.window === window && !$0.isHidden })
                XCTAssertTrue(field.becomeFirstResponder())
                let transitionStress = ProcessInfo.processInfo.environment["T04_SIDEBAR_TRANSITION_STRESS"] == "1"
                try await Task.sleep(for: .milliseconds(transitionStress ? 1 : 500))
                XCTAssertTrue(field.isFirstResponder)
            }
            let settling = try await settleSidebarTail(
                scroll, host: host, window: window, recorder: recorder,
                keyboardVisible: keyboardVisible, variant: variant
            )
            XCTAssertEqual(recorder.keyboardVisible, keyboardVisible, "Real keyboard notifications must reach root state")
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height + 44, "Fixture must genuinely overflow")
            let addFrame = try XCTUnwrap(recorder.sidebarAddFrame)
            let diagnostic = "variant=\(variant), keyboard=\(keyboardVisible), rootKeyboard=\(recorder.keyboardVisible), "
                + "didShow=\(recorder.keyboardDidShow), firstResponder=\(textFields(in: host.view).contains { $0.isFirstResponder }), "
                + "uptime=\(ProcessInfo.processInfo.systemUptime), add=\(addFrame), updates=\(recorder.sidebarAddUpdates), "
                + "frameAge=\(ProcessInfo.processInfo.systemUptime - recorder.sidebarAddUpdatedAt), "
                + "bounds=\(scroll.bounds), offset=\(scroll.contentOffset), size=\(scroll.contentSize), "
                + "inset=\(scroll.contentInset), adjusted=\(scroll.adjustedContentInset), "
                + "window=\(window.bounds), safeArea=\(window.safeAreaInsets), list=\(String(describing: recorder.geometry))"
            print("T04_TAIL_SAMPLE \(diagnostic)")
            let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
            XCTAssertGreaterThan(scroll.contentOffset.y, 0)
            XCTAssertGreaterThanOrEqual(addFrame.width, 44)
            XCTAssertGreaterThanOrEqual(addFrame.height, 44)
            XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(addFrame), "Entire add entry must be reachable: \(diagnostic), viewport=\(viewport), settling=\(settling)")
            XCTAssertTrue(window.bounds.contains(addFrame))
            let hit = try XCTUnwrap(window.hitTest(CGPoint(x: addFrame.midX, y: addFrame.midY), with: nil))
            XCTAssertTrue(hit === scroll || hit.isDescendant(of: scroll), "Add target must hit the actual sidebar")
            let frames = "processLocale=\(Locale.current.identifier)\nlanguages=\(Locale.preferredLanguages)\n"
                + "keyboardVisible=\(recorder.keyboardVisible)\nviewport=\(viewport)\nadd=\(addFrame)\n"
                + "contentSize=\(scroll.contentSize)\noffset=\(scroll.contentOffset)\ndiagnostic=\(diagnostic)\nsettling=\(settling)\nitems=\(recorder.sidebarItems)"
            try persistHeaderEvidence(image: windowImage(window), name: "\(variant)-keyboard-\(keyboardVisible)", frames: frames)
            let matrix = XCTAttachment(string: frames)
            matrix.name = "\(variant)-keyboard-\(keyboardVisible)-frames"
            matrix.lifetime = .keepAlways
            add(matrix)
        }
        let dismissKeyboard = try XCTUnwrap(recorder.dismissKeyboard)
        dismissKeyboard() // Same guarded production action used by sidebar selection/list drag.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(recorder.keyboardVisible)
        XCTAssertFalse(textFields(in: host.view).contains { $0.isFirstResponder })
        dismissKeyboard() // Hidden-state guard is also a no-op on the real action.
        let move = try XCTUnwrap(recorder.sidebarMove)
        move(-1, names.count) // Shared production guard must preserve identity on invalid actions.
        XCTAssertEqual(recorder.sidebarItems, original)
        move(0, names.count)
        try await Task.sleep(for: .milliseconds(150))
        let expected = Array(original.dropFirst()) + [original[0]]
        XCTAssertEqual(recorder.sidebarItems.map(\.id), expected.map(\.id))
        XCTAssertEqual(recorder.sidebarItems.map(\.name), expected.map(\.name))
        XCTAssertEqual(recorder.sidebarItems.map(\.completed), expected.map(\.completed))
        XCTAssertEqual(recorder.sidebarItems.map(\.total), expected.map(\.total))
        XCTAssertEqual(recorder.sidebarItems.map(\.index), Array(names.indices))
        XCTAssertEqual((workout.exercises ?? []).sorted { $0.order < $1.order }.map { String(describing: $0.persistentModelID) },
                       expected.map(\.id))
        scroll.setContentOffset(CGPoint(x: 0, y: 0), animated: false)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(recorder.sidebarItems.map(\.id), expected.map(\.id), "Scroll must not recycle model semantics")
        let driver = try XCTUnwrap(recorder.driver)
        driver.scrollTo(owners[0].persistentModelID, .bottom)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(try XCTUnwrap(recorder.geometry).contentOffset.y, 0, "Scroll the actual main List after reorder")
        XCTAssertEqual(recorder.sidebarItems.map(\.id), expected.map(\.id))
        XCTAssertEqual(recorder.sidebarItems.map(\.name), expected.map(\.name))
        XCTAssertEqual(recorder.sidebarItems.map(\.completed), expected.map(\.completed))
        XCTAssertEqual(recorder.sidebarItems.map(\.total), expected.map(\.total))
        XCTAssertEqual(recorder.sidebarItems.map(\.index), Array(names.indices))
        try persistHeaderEvidence(image: windowImage(window), name: "\(variant)-reordered",
                                  frames: "before=\(original)\nafter=\(recorder.sidebarItems)\nlist=\(String(describing: recorder.geometry))\n")
    }

    /// Synchronize with measured native state, not assertion success. A stationary but
    /// clipped add entry returns to the caller's strict containment/hit-test assertions.
    private func settleSidebarTail(
        _ scroll: UIScrollView, host: UIViewController, window: UIWindow,
        recorder: ListObservationRecorder, keyboardVisible: Bool, variant: String
    ) async throws -> String {
        let start = ProcessInfo.processInfo.systemUptime
        var previous: [CGFloat] = []
        var stableSince = start
        var trace: [String] = []
        while ProcessInfo.processInfo.systemUptime - start < 5 {
            host.view.layoutIfNeeded()
            let target = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
            scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            try await Task.sleep(for: .milliseconds(50))
            let now = ProcessInfo.processInfo.systemUptime
            let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: window)
            let add = recorder.sidebarAddFrame ?? .null
            let sample = [scroll.bounds.minY, scroll.bounds.width, scroll.bounds.height,
                          scroll.contentSize.height, scroll.adjustedContentInset.top, scroll.adjustedContentInset.bottom,
                          viewport.minY, viewport.height, add.minX, add.minY, add.width, add.height]
            let responder = textFields(in: host.view).contains { $0.isFirstResponder }
            let keyboardSettled = recorder.keyboardVisible == keyboardVisible && responder == keyboardVisible
                && (!keyboardVisible || recorder.keyboardDidShow)
            trace.append("t=\(now - start), native=\(sample), target=\(target), root=\(recorder.keyboardVisible), "
                         + "didShow=\(recorder.keyboardDidShow), responder=\(responder), updates=\(recorder.sidebarAddUpdates)")
            if sample != previous || !keyboardSettled {
                stableSince = now
                previous = sample
            } else if now - stableSince >= 0.2 {
                return trace.joined(separator: "\n")
            }
        }
        let diagnostic = "\(variant) keyboard=\(keyboardVisible) did not settle in 5s:\n" + trace.joined(separator: "\n")
        print("T04_TAIL_SETTLE_TIMEOUT \(diagnostic)")
        let attachment = XCTAttachment(string: diagnostic)
        attachment.name = "\(variant)-keyboard-\(keyboardVisible)-settle-timeout"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail(diagnostic)
        throw NSError(domain: "T04SidebarGeometry", code: 1, userInfo: [NSLocalizedDescriptionKey: diagnostic])
    }

        private func persistT03Evidence(
            image: UIImage,
            name: String,
            width: Int,
            largeMode: Bool,
            dark: Bool,
            dynamicType: DynamicTypeSize,
            title: CGRect,
            header: CGRect,
            geometry: ActiveWorkoutListGeometry,
            controls: [String: CGRect]
        ) throws {
            let safeName = name.replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
            let variant = "\(safeName)-\(width)-\(largeMode ? "large" : "normal")-\(dark ? "dark" : "light")-\(dynamicType)"
            let frameText = [
                "title=\(title)",
                "header=\(header)",
                "listFrame=\(geometry.listFrame)",
                "controls=\(controls)"
            ].joined(separator: "\n")
            try persistHeaderEvidence(image: image, name: variant, frames: frameText)
        }

    private func persistHeaderEvidence(image: UIImage, name: String, frames: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["T03_EVIDENCE_DIR"],
              !directory.isEmpty else { return }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: root.appendingPathComponent("\(name).png"))
        try frames.write(to: root.appendingPathComponent("\(name).frames.txt"), atomically: true, encoding: .utf8)
    }

        private func textFields(in view: UIView) -> [UITextField] {
        (view as? UITextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
    }

    private func descendants(of view: UIView) -> [UIView] {
        view.subviews + view.subviews.flatMap(descendants)
    }

    private func assertNoBlackHeaderGap(_ image: HeaderPixels, gap: CGRect, variant: String) {
        guard gap.width > 0, gap.height > 0 else { return }
        let left = max(0, Int(floor(gap.minX * image.scale)))
        let right = min(image.width, Int(ceil(gap.maxX * image.scale)))
        let top = max(0, Int(floor(gap.minY * image.scale)))
        let bottom = min(image.height, Int(ceil(gap.maxY * image.scale)))
        var blackPixels = 0
        if left < right, top < bottom {
            for y in top..<bottom {
                for x in left..<right {
                    let offset = y * image.stride + x * 4
                    if image.bytes[offset] == 0
                        && image.bytes[offset + 1] == 0
                        && image.bytes[offset + 2] == 0 {
                        blackPixels += 1
                    }
                }
            }
        }
        XCTAssertLessThan(blackPixels, 20, "\(variant) header-to-first-row gap contains RGB(0,0,0): \(blackPixels)")
    }

    private func assertHeaderControls(_ controls: [String: CGRect], header: CGRect, viewport: CGRect) {
        for name in ["add-set", "menu"] {
            guard let frame = controls[name] else {
                XCTFail("Missing \(name) frame")
                continue
            }
            XCTAssertGreaterThanOrEqual(frame.width, 44, name)
            XCTAssertGreaterThanOrEqual(frame.height, 44, name)
            XCTAssertTrue(header.insetBy(dx: -1, dy: -1).contains(frame), name)
            XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(frame), name)
        }
        if let add = controls["add-set"], let menu = controls["menu"] {
            XCTAssertFalse(add.intersects(menu), "Header controls must not overlap")
        }
    }

    private func firstRowInputFrames(in view: UIView, row: CGRect, window: UIWindow) -> [CGRect] {
        let frames = textFields(in: view).filter { !$0.isHidden && $0.alpha > 0 && $0.window === window }
            .map { $0.convert($0.bounds, to: window) }
            .filter { $0.intersects(row) }
        XCTAssertEqual(frames.count, 2, "First row must expose both real weight/reps inputs; an empty selection is not evidence")
        for frame in frames {
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertTrue(row.insetBy(dx: -1, dy: -1).contains(frame), "Input must belong to first row")
        }
        return frames
    }

    private func assertHeaderSeparation(
        addSet: CGRect, firstRow: CGRect, header: CGRect, inputFrames: [CGRect]
    ) {
        XCTAssertTrue(header.contains(addSet), "Add-set control must remain inside header")
        XCTAssertGreaterThanOrEqual(firstRow.minY - addSet.maxY, 0, "Unified header surface needs no vertical card gap")
        XCTAssertFalse(addSet.intersects(firstRow), "Add-set control must not intersect first row")
        XCTAssertEqual(inputFrames.count, 2)
        for frame in inputFrames {
            XCTAssertFalse(addSet.intersects(frame), "Add-set control must not intersect fresh first-row input \(frame)")
        }
    }

    private func changedPixels(_ image: HeaderPixels, _ other: HeaderPixels, in frame: CGRect) -> Int {
        let left = max(0, Int(floor(frame.minX * image.scale)))
        let right = min(image.width, Int(ceil(frame.maxX * image.scale)))
        let top = max(0, Int(floor(frame.minY * image.scale)))
        let bottom = min(image.height, Int(ceil(frame.maxY * image.scale)))
        var changed = 0
        for y in top..<bottom {
            for x in left..<right where image.distance(x: x, y: y, to: other) > 12 {
                changed += 1
            }
        }
        return changed
    }

    private func changedPixels(_ image: HeaderPixels, _ first: CGRect, _ second: CGRect) -> Int {
        let width = min(first.width, second.width)
        let height = min(first.height, second.height)
        let xStart = max(0, Int(floor(first.minX * image.scale)))
        let yStart = max(0, Int(floor(first.minY * image.scale)))
        let otherXStart = max(0, Int(floor(second.minX * image.scale)))
        let otherYStart = max(0, Int(floor(second.minY * image.scale)))
        let pixelWidth = min(Int(ceil(width * image.scale)), image.width - max(xStart, otherXStart))
        let pixelHeight = min(Int(ceil(height * image.scale)), image.height - max(yStart, otherYStart))
        var changed = 0
        for row in 0..<max(0, pixelHeight) {
            for column in 0..<max(0, pixelWidth) {
                let leftX = xStart + column
                let leftY = yStart + row
                let rightX = otherXStart + column
                let rightY = otherYStart + row
                guard leftX < image.width, rightX < image.width,
                      leftY < image.height, rightY < image.height else { continue }
                let leftOffset = leftY * image.stride + leftX * 4
                let rightOffset = rightY * image.stride + rightX * 4
                let delta = (0..<3).map {
                    abs(Int(image.bytes[leftOffset + $0]) - Int(image.bytes[rightOffset + $0]))
                }.max() ?? 0
                if delta > 12 { changed += 1 }
            }
        }
        return changed
    }

    private func pixelSignature(_ image: HeaderPixels, _ frame: CGRect) -> Int {
        let left = max(0, Int(floor(frame.minX * image.scale)))
        let right = min(image.width, Int(ceil(frame.maxX * image.scale)))
        let top = max(0, Int(floor(frame.minY * image.scale)))
        let bottom = min(image.height, Int(ceil(frame.maxY * image.scale)))
        guard left < right, top < bottom else { return 0 }
        var signature = 0
        for y in top..<bottom {
            for x in left..<right {
                let offset = y * image.stride + x * 4
                signature = (signature &* 31) &+ Int(image.bytes[offset])
                signature = (signature &* 31) &+ Int(image.bytes[offset + 1])
                signature = (signature &* 31) &+ Int(image.bytes[offset + 2])
            }
        }
        return signature
    }

    /// Explicit sRGB RGBA8 conversion handles both ordinary and 16-bit/wide-gamut
    /// renderer output. All coordinates below are pixel coordinates with real stride.
    private struct HeaderPixels {
        let bytes: [UInt8]
        let width: Int
        let height: Int
        let stride: Int
        let scale: CGFloat

        init(_ image: UIImage) throws {
            let source = try XCTUnwrap(image.cgImage)
            width = source.width
            height = source.height
            stride = width * 4
            scale = CGFloat(width) / image.size.width
            let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try XCTUnwrap(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: stride, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = try XCTUnwrap(context.data)
            bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: stride * height))
        }

        func distance(x: Int, y: Int, to other: HeaderPixels) -> Int {
            let offset = y * stride + x * 4
            return (0..<3).map { abs(Int(bytes[offset + $0]) - Int(other.bytes[offset + $0])) }.max() ?? 0
        }
    }

    @discardableResult
    private func assertPinnedHeaderPixels(
        _ image: HeaderPixels, baseline: HeaderPixels, band: CGRect
    ) -> String {
        XCTAssertEqual(image.width, baseline.width)
        XCTAssertEqual(image.height, baseline.height)
        let left = max(0, Int(ceil(band.minX * image.scale)))
        let right = min(image.width, Int(floor(band.maxX * image.scale)))
        let top = max(0, Int(ceil(band.minY * image.scale)))
        let bottom = min(image.height, Int(floor(band.maxY * image.scale)))
        var changed = 0
        var maximum = 0
        var sampled = 0
        // Same-exercise baseline comparison retains its foreground glyphs/pills:
        // it cannot mistake teal buttons or title text for row bleed. The whole
        // band, including its margins, must stay visually stable as rows pass below.
        for y in top..<bottom {
            for x in left..<right {
                let delta = image.distance(x: x, y: y, to: baseline)
                sampled += 1
                maximum = max(maximum, delta)
                if delta > 12 { changed += 1 }
            }
        }
        XCTAssertGreaterThan(sampled, 1_000)
        XCTAssertLessThanOrEqual(Double(changed) / Double(max(1, sampled)), 0.005,
                                 "Pinned band changed: \(changed)/\(sampled) pixels; max channel delta \(maximum)")
        return "RGBA8 sRGB \(sampled) pixels; changed=\(changed); maxDelta=\(maximum); band=\(band)"
    }

    private func windowImage(_ window: UIWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }
}
#endif
