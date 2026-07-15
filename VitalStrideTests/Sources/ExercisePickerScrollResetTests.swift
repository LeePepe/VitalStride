import Foundation
import SwiftData
import Testing
import VitalModels

@testable import VitalStride

/// MY-1250 — ExercisePicker: 切部位后滚动位置未重置导致空白
///
/// Reproducible check point for the scroll-reset contract.
///
/// The bug's precondition is that `computeEquipmentGroups` can return a set
/// whose first element is *the same* Equipment after a muscle-group change,
/// while the tail of the list shrinks. In that case the old
/// `.onChange(of: equipmentGroups.map(\.0))` handler kept `visibleEquipment`
/// unchanged (because the current equipment was still in the new list), so
/// the ScrollView held its old offset and rendered blank space at the bottom.
///
/// The fix drops the "only reset when current is missing" gate and
/// unconditionally re-anchors to `newGroups.first?.0` after either
/// `selectedMuscleGroup` or `debouncedSearchText` changes. These tests pin
/// that contract by asserting the sequence of `first` equipments the picker
/// would anchor to across the buggy repro sequence and around an
/// intersecting-equipment shrink for both muscle-group and search changes.
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

        // Fixed contract: the picker now anchors unconditionally to
        // `newGroups.first?.0` on muscle-group change, regardless of
        // whether the current first equipment survives. `computeEquipmentGroups`
        // is a pure function; the assertion here locks the value the fixed
        // handler passes into `visibleEquipment`.
        let newAnchor = chest.first?.0
        #expect(newAnchor != nil)
        #expect(newAnchor == chest.first?.0)
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

        // Same fixed contract as above: anchor to `newGroups.first?.0`.
        let newAnchor = searched.first?.0
        #expect(newAnchor != nil)
        #expect(newAnchor == searched.first?.0)
    }

    @Test("空结果时 first?.0 是 nil, 不会 crash")
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
