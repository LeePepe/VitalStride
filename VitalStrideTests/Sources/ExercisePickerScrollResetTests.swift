import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// MY-1250 — ExercisePicker: 切部位后滚动位置未重置导致空白
///
/// Reproducible check point for the scroll-reset contract.
///
/// **MY-1272 refinement.** Muscle-group changes now prefer the current
/// `visibleEquipment` when it survives the new filter (parent MY-1271
/// acceptance: 切部位 → 滚到当前 `visibleEquipment` 对应 section 顶,
/// 若不在新列表则回退到第一个 section). Search-driven changes still
/// unconditionally re-anchor to `newGroups.first?.0` because the user
/// changed intent (search bar reset).
///
/// These tests pin both contracts:
/// • Search path — locks the search-driven scroll to first-section
///   fallback that the MY-1250 fix originally introduced (unchanged).
/// • Muscle-group path — locks the MY-1272 refinement: pin to the
///   previously visible equipment when present, fall back to the first
///   section when absent, and return `nil` when the new list is empty.
@Suite("ExercisePicker scroll reset (MY-1250)")
struct ExercisePickerScrollResetTests {
    let container: ModelContainer

    init() throws {
        container = try ModelContainerConfiguration.makeTestContainer()
    }

    private func makeExercise(
        _ context: ModelContext,
        nameEn: String,
        nameZh: String,
        muscleGroup: MuscleGroup,
        equipment: Equipment
    ) -> Exercise {
        let exercise = Exercise(
            nameEn: nameEn,
            nameZh: nameZh,
            muscleGroup: muscleGroup,
            equipment: equipment
        )
        context.insert(exercise)
        return exercise
    }

    /// Fixture spanning multiple equipments across two muscle groups so that
    /// "all → chest" leaves a strict subset (chest has fewer equipments than
    /// "all"), while still preserving at least one Equipment that appears in
    /// both — that is the exact buggy precondition for MY-1250.
    private func makeMY1250Library(_ context: ModelContext) {
        _ = makeExercise(context, nameEn: "Bench Press", nameZh: "杠铃卧推",
                         muscleGroup: .chest, equipment: .barbell)
        _ = makeExercise(context, nameEn: "Dumbbell Fly", nameZh: "哑铃飞鸟",
                         muscleGroup: .chest, equipment: .dumbbell)
        _ = makeExercise(context, nameEn: "Cable Fly", nameZh: "绳索飞鸟",
                         muscleGroup: .chest, equipment: .cable)

        _ = makeExercise(context, nameEn: "Barbell Row", nameZh: "杠铃划船",
                         muscleGroup: .back, equipment: .barbell)
        _ = makeExercise(context, nameEn: "Dumbbell Row", nameZh: "哑铃划船",
                         muscleGroup: .back, equipment: .dumbbell)
        _ = makeExercise(context, nameEn: "Cable Pulldown", nameZh: "绳索下拉",
                         muscleGroup: .back, equipment: .cable)
        _ = makeExercise(context, nameEn: "Chin Up", nameZh: "引体向上",
                         muscleGroup: .back, equipment: .bodyweight)
    }

    @Test("切'全部'→'胸部'时 first equipment 会被重锚 (MY-1250 repro)")
    func muscleGroupChangeReanchorsFirstEquipment() throws {
        let context = ModelContext(container)
        makeMY1250Library(context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        // "全部" — union of chest + back.
        let all = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: nil,
            searchText: ""
        )
        // "胸部" only — strict subset that still contains the first equipment
        // of "全部" (both include e.g. .barbell in Equipment.allCases order).
        let chest = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: .chest,
            searchText: ""
        )

        // Precondition MY-1250 depends on: after switching to a
        // strictly-smaller muscle group, at least the FIRST equipment
        // remains in both lists (so the *old* gated `.onChange` would have
        // left `visibleEquipment` unchanged), but the tail of the list
        // shrinks.
        #expect(all.count > chest.count)
        try #require(!all.isEmpty)
        try #require(!chest.isEmpty)
        #expect(all.first?.0 == chest.first?.0)

        // Fixed contract (MY-1250 base + MY-1272 refinement): the picker
        // now scrolls to `resolveMuscleGroupScrollAnchor(previouslyVisible,
        // in: newOrder)` on muscle-group change. When the previously
        // visible equipment (`.barbell`) is still present in the new
        // filter (chest also has `.barbell`), the anchor MUST pin to
        // that equipment — not blindly reset to `newGroups.first?.0`.
        // Since `.barbell` IS the first section of chest, the assertion
        // holds either way; the stronger MY-1272 branch is covered by
        // `muscleGroupChangePreservesVisibleEquipmentWhenPresent`.
        let anchor = ExercisePickerView.resolveMuscleGroupScrollAnchor(
            previouslyVisible: all.first?.0,
            in: chest.map(\.0)
        )
        #expect(anchor != nil)
        #expect(anchor == chest.first?.0)
    }

    @Test("MY-1272: 切部位时保留 visibleEquipment（当它仍存在于新列表时）")
    func muscleGroupChangePreservesVisibleEquipmentWhenPresent() throws {
        let context = ModelContext(container)
        makeMY1250Library(context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        // Both "全部" and "胸部" contain .dumbbell — but .dumbbell is NOT
        // the first equipment of either list. This is the discriminating
        // case: MY-1250 fallback would return `.barbell` (first section);
        // MY-1272 must return `.dumbbell` because the user was reading
        // the dumbbell section and it survives the filter.
        let chest = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: .chest,
            searchText: ""
        )
        let chestEquipments = chest.map(\.0)
        try #require(chestEquipments.contains(.dumbbell))
        try #require(chestEquipments.first != .dumbbell)

        let anchor = ExercisePickerView.resolveMuscleGroupScrollAnchor(
            previouslyVisible: .dumbbell,
            in: chestEquipments
        )
        #expect(anchor == .dumbbell,
                "muscle-group change must pin to the survived visibleEquipment, not the first section")
    }

    @Test("MY-1272: 切部位时 visibleEquipment 不在新列表 → 回退到第一个 section")
    func muscleGroupChangeFallsBackToFirstWhenVisibleEquipmentAbsent() throws {
        // Simulate: user was on `.machine` (not in chest fixture) then
        // switched to chest. Fallback MUST be the new first section.
        let context = ModelContext(container)
        makeMY1250Library(context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        let chest = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: .chest,
            searchText: ""
        )
        let chestEquipments = chest.map(\.0)
        try #require(!chestEquipments.contains(.machine))

        let anchor = ExercisePickerView.resolveMuscleGroupScrollAnchor(
            previouslyVisible: .machine,
            in: chestEquipments
        )
        #expect(anchor == chestEquipments.first)
    }

    @Test("MY-1272: 切部位时 visibleEquipment 为 nil → 回退到第一个 section")
    func muscleGroupChangeFallsBackWhenPreviouslyNil() throws {
        // First-open path: no `visibleEquipment` yet. Anchor MUST be the
        // new first section (preserves MY-1250 base behavior for the
        // "no prior scroll intent" case).
        let context = ModelContext(container)
        makeMY1250Library(context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        let chest = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: .chest,
            searchText: ""
        )
        let anchor = ExercisePickerView.resolveMuscleGroupScrollAnchor(
            previouslyVisible: nil,
            in: chest.map(\.0)
        )
        #expect(anchor == chest.first?.0)
    }

    @Test("MY-1272: 切部位到空结果 → anchor 为 nil, 不 crash")
    func muscleGroupChangeToEmptyReturnsNil() {
        let anchor = ExercisePickerView.resolveMuscleGroupScrollAnchor(
            previouslyVisible: .barbell,
            in: []
        )
        #expect(anchor == nil)
    }

    @Test("搜索文本变化后 first equipment 也会被重锚")
    func searchTextChangeReanchorsFirstEquipment() throws {
        let context = ModelContext(container)
        makeMY1250Library(context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        // Empty search: full "全部" content.
        let unfiltered = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: nil,
            searchText: ""
        )
        // A search that keeps entries in the *first* equipment bucket but
        // drops the tail — same shape as the muscle-group bug.
        let searched = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: nil,
            searchText: "Press"
        )

        try #require(!unfiltered.isEmpty)
        try #require(!searched.isEmpty)
        #expect(unfiltered.count >= searched.count)

        // MY-1259: exercise the production helper the search handler
        // routes through. Comparing the helper's return against the
        // independently-computed `searched.first?.0` (not the same
        // expression on both sides) locks the "search always anchors to
        // first section" policy. If the helper regressed to e.g. return
        // the last section, this assertion would fail — the previous
        // tautology (`searched.first?.0 == searched.first?.0`) would not.
        let anchor = ExercisePickerView.resolveSearchScrollAnchor(
            in: searched.map(\.0)
        )
        #expect(anchor != nil)
        #expect(anchor == searched.first?.0,
                "search-driven reset must anchor to the first section of the filtered list")
    }

    @Test("MY-1259: 搜索到空结果 → resolveSearchScrollAnchor 返回 nil, 不 crash")
    func searchAnchorReturnsNilForEmptyResult() throws {
        let context = ModelContext(container)
        makeMY1250Library(context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        // Search string guaranteed not to match any localized name.
        let noMatch = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: nil,
            searchText: "zzz-no-match-\(UUID().uuidString)"
        )
        #expect(noMatch.isEmpty)

        // MY-1259: empty-result policy is `nil` so the handler can safely
        // clear scroll state without a `guard` at every call site.
        // Mirrors `resolveMuscleGroupScrollAnchor(..., in: [])`.
        let anchor = ExercisePickerView.resolveSearchScrollAnchor(
            in: noMatch.map(\.0)
        )
        #expect(anchor == nil)
    }

    @Test("MY-1259: 空结果时 first?.0 是 nil, 不会 crash")
    func emptyResultAnchorsToNil() throws {
        let context = ModelContext(container)
        makeMY1250Library(context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        // Search string guaranteed not to match any localized name.
        let noMatch = ExercisePickerView.computeEquipmentGroups(
            from: exercises,
            muscleGroup: nil,
            searchText: "zzz-no-match-\(UUID().uuidString)"
        )

        #expect(noMatch.isEmpty)
        // The fix passes `newGroups.first?.0` into `visibleEquipment`.
        // When empty, that is `nil` — must not crash.
        let anchor: Equipment? = noMatch.first?.0
        #expect(anchor == nil)
    }
}
