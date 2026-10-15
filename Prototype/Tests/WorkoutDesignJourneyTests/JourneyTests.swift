import Foundation
@testable import Prototype
import Testing

@Test @MainActor
func selectAcrossFiltersThenReturnToWorkout() {
    let session = StudioSession()
    session.selectedIDs = []
    session.toggleSelection("row")
    session.muscle = "chest"
    session.toggleSelection("bench")
    session.query = "ZZZZ"
    #expect(session.results.isEmpty)
    #expect(session.selectedIDs == ["row", "bench"])
    session.clearFilters()
    session.toggleSelection("row")
    session.toggleSelection("row")
    #expect(session.selectedIDs == ["bench", "row"])
    session.confirmSelection()
    #expect(session.screen == .workout)
    #expect(session.workoutIDs.contains("row"))
    #expect(session.setsByExercise["row"]?.count == 1)
}

@Test @MainActor
func editCompleteDeleteUndoPreservesRestAndValues() {
    let session = StudioSession(screen: .workout)
    let before = session.activeSets
    session.beginEditing("weight")
    session.editorValue = "62.5"
    session.commitEditor()
    session.beginEditing("reps")
    session.editorValue = "9"
    session.commitEditor()
    session.complete()
    let end = session.restEnd
    #expect(end != nil)
    #expect(session.activeSets[2].weight == 62.5)
    #expect(session.activeSets[2].reps == 9)
    #expect(session.activeSets[2].completed)
    session.deleteSet(3)
    session.undoDelete()
    #expect(session.activeSets[2].completed)
    #expect(session.activeSets[2].weight == 62.5)
    #expect(session.restEnd == end)
    session.complete(3)
    #expect(!session.activeSets[2].completed)
    #expect(session.restEnd == nil)
    #expect(session.activeSets.count == before.count)
}

@Test @MainActor
func replaceExercisePreservesSetDataAndOrdering() {
    let session = StudioSession(screen: .workout)
    let original = session.activeSets
    session.replacementID = "bench"
    session.screen = .picker
    session.toggleSelection("row")
    #expect(session.workoutIDs.first == "row")
    #expect(session.activeSets == original)
    #expect(session.activeExerciseID == "row")
    #expect(session.screen == .workout)
    #expect(session.setsByExercise["bench"] == nil)
}

@Test
func searchCombinesEquipmentMuscleAndBilingualTerms() {
    #expect(StudioExercise.search(StudioExercise.fixtures, query: "  BENCH  ", muscle: "chest", equipment: "barbell").map(\.id) == ["bench"])
    #expect(StudioExercise.search(StudioExercise.fixtures, query: "卧推", muscle: "chest", equipment: "all").map(\.id) == ["bench", "incline"])
    #expect(StudioExercise.search(StudioExercise.fixtures, query: "bench", muscle: "legs", equipment: "all").isEmpty)
}

@Test @MainActor
func keyboardReplacesSelectionAndKeepsBothFieldsUntilSave() {
    let session = StudioSession(screen: .workout)
    session.beginEditing("weight")
    for key in ["6", "2", ".", "5"] { session.pressEditorKey(key) }
    #expect(session.editorValue == "62.5")
    session.switchEditor(to: "reps")
    session.pressEditorKey("9")
    session.pressEditorKey(".")
    #expect(session.editorValue == "9")
    session.switchEditor(to: "weight")
    #expect(session.editorValue == "62.5")
    #expect(session.currentSet?.weight == 60)
    session.commitEditor()
    #expect(session.currentSet?.weight == 62.5)
    #expect(session.currentSet?.reps == 9)
    #expect(session.editorField == nil)
    #expect(session.restEnd == nil)
}

@Test @MainActor
func keyboardRejectsInvalidInputAndCancelDiscardsBothDraftFields() {
    let session = StudioSession(screen: .workout, scenario: .resting)
    let original = session.activeSets
    let rest = session.restEnd
    session.beginEditing("weight")
    session.pressEditorKey("delete")
    #expect(session.editorValue.isEmpty)
    #expect(!session.editorCanCommit)
    session.commitEditor()
    #expect(session.editorField != nil)
    for key in [".", "5", ".", "5", "5"] { session.pressEditorKey(key) }
    #expect(session.editorValue == "0.55")
    session.switchEditor(to: "reps")
    session.pressEditorKey("0")
    #expect(!session.editorCanCommit)
    session.commitEditor(completeSet: true)
    #expect(session.activeSets == original)
    #expect(session.restEnd == rest)
    session.cancelEditor()
    #expect(session.activeSets == original)
    #expect(session.editorField == nil)
    session.beginEditing("weight")
    session.deleteSet(3)
    #expect(session.editorField == nil)
    session.undoDelete()
    #expect(session.activeSets == original)
}

@Test @MainActor
func keyboardPresetsCopyThenLogsOneSetAndStartsRest() {
    let session = StudioSession(screen: .workout)
    session.beginEditing("weight")
    session.adjustEditor(2.5)
    session.presetEditorReps(12)
    session.copyEditorToNext()
    #expect(session.activeSets[3].weight == 62.5)
    #expect(session.activeSets[3].reps == 12)
    #expect(!session.activeSets[2].completed)
    session.commitEditor(completeSet: true)
    #expect(session.activeSets[2].completed)
    #expect(session.activeSets[2].weight == 62.5)
    #expect(session.activeSets[2].reps == 12)
    #expect(session.currentSet?.id == 4)
    #expect(session.restEnd != nil)
    session.commitEditor(completeSet: true)
    #expect(!session.activeSets[3].completed)
}

@Test @MainActor
func keyboardTargetRemainsStableAndCopyAppendsAtTheEnd() {
    let session = StudioSession(screen: .workout)
    session.activeExerciseID = "incline"
    session.setsByExercise["incline"] = [.init(id: 42, weight: 20, reps: 8, completed: false, kind: "working")]
    session.beginEditing("weight")
    session.usePreviousEditorValues()
    session.copyEditorToNext()
    #expect(session.setsByExercise["incline"]?.count == 2)
    #expect(session.setsByExercise["incline"]?.last?.weight == 24)
    session.activeExerciseID = "bench"
    session.commitEditor()
    #expect(session.setsByExercise["incline"]?.first?.weight == 24)
    #expect(session.activeSets[2].weight == 60)
}
