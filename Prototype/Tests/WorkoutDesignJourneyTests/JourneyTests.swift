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

@Test @MainActor
func compactEditingTargetsAnySetAndCancelsAllDraftFields() {
    let session = CompactSession()
    #expect(session.select(exercise: "bench", setID: 4))
    session.edit("weight")
    session.core.pressEditorKey("7")
    session.core.pressEditorKey("0")
    session.setRPE(9); session.setKind("warmup")
    session.discardDraft()
    #expect(session.core.activeSets[3].weight == 60)
    #expect(session.core.activeSets[3].kind == "working")
    #expect(session.currentRPE == nil)
    session.edit("weight")
    session.core.pressEditorKey("7"); session.core.pressEditorKey("0")
    session.setRPE(8); session.setKind("warmup")
    session.save()
    #expect(session.core.activeSets[3].weight == 70)
    #expect(session.core.activeSets[2].weight == 60)
    #expect(session.currentRPE == 8)
    #expect(session.core.activeSets[3].kind == "warmup")
    #expect(!session.core.activeSets[3].completed)
}

@Test @MainActor
func compactInvalidDraftKeepsTargetAndValidSwitchSavesWithoutLogging() {
    let session = CompactSession()
    session.edit("reps"); session.core.pressEditorKey("0")
    #expect(!session.select(exercise: "incline"))
    #expect(session.core.activeExerciseID == "bench")
    session.core.pressEditorKey("delete"); session.core.pressEditorKey("8")
    #expect(session.select(exercise: "incline"))
    #expect(session.core.setsByExercise["bench"]?[2].reps == 8)
    #expect(session.core.setsByExercise["bench"]?[2].completed == false)
    #expect(session.core.restEnd == nil)
    #expect(!session.select(exercise: "incline", setID: 999))
}

@Test @MainActor
func compactPickerCachesSectionsAcrossSelectionAndReturnsInChosenOrder() {
    let model = CompactPickerModel()
    let session = CompactSession(picker: true)
    let initial = model.generation
    session.core.toggleSelection("fly"); session.core.toggleSelection("bench")
    model.refresh()
    #expect(model.generation == initial)
    model.muscle = "chest"; model.query = "dumbbell"; model.refresh()
    #expect(model.sections.flatMap(\.items).map(\.id) == ["incline"])
    session.core.toggleSelection("incline")
    model.reset()
    #expect(session.core.selectedIDs == ["fly", "bench", "incline"])
    #expect(model.resultCount == StudioExercise.fixtures.count)
}

@Test @MainActor
func compactTrainingActionsKeepVisibleNumberAndCompletionIntent() {
    let session = CompactSession()
    session.select(exercise: "bench", setID: 2)
    session.edit("reps"); session.core.pressEditorKey("9")
    session.completeSelected()
    #expect(session.selectedSet?.completed == false)
    #expect(session.selectedSet?.reps == 9)
    session.completeSelected()
    #expect(session.core.activeSets[1].completed)
    let rest = session.core.restEnd
    session.addSet()
    #expect(session.selectedSetNumber == 5)
    let addedID = session.selectedSetID
    session.deleteSelected()
    #expect(session.core.activeSets.count == 4)
    session.core.undoDelete()
    #expect(session.core.activeSets.last?.id == addedID)
    #expect(session.core.restEnd == rest)
    session.select(exercise: "bench", setID: addedID)
    session.edit("weight"); session.core.pressEditorKey("7"); session.core.pressEditorKey("5")
    session.showPicker()
    #expect(session.core.activeSets.last?.weight == 75)
    #expect(session.core.screen == .picker)
    session.core.confirmSelection()
    session.edit("reps"); session.core.pressEditorKey("8")
    session.finish()
    #expect(session.core.activeSets.last?.reps == 8)
    #expect(session.core.isFinished)
    #expect(session.core.restEnd == nil)
    #expect(session.core.editorField == nil)
}

@Test @MainActor
func browsingOtherExercisesNeverRebindsOrCommitsTheDraft() {
    let session = CompactSession()
    session.edit("weight"); session.core.pressEditorKey("7"); session.core.pressEditorKey("0")
    let target = session.target
    session.navigation.observeVisible(["incline", "fly"], order: session.core.workoutIDs)
    #expect(session.navigation.visibleExerciseID == "incline")
    #expect(session.target == target)
    #expect(session.core.editorWeightText == "70")
    #expect(session.core.activeSets[2].weight == 60)
    #expect(session.navigation.jumpRevision == 0)
    session.navigation.jump(to: target.exerciseID, order: session.core.workoutIDs)
    #expect(session.navigation.visibleExerciseID == "bench")
    #expect(session.core.editorField != nil)
    session.save()
    #expect(session.core.setsByExercise["bench"]?[2].weight == 70)
    #expect(session.core.setsByExercise["incline"]?[2].weight == 24)
}

@Test @MainActor
func sectionNavigationIgnoresEmptyAndUnknownVisibilityAndAllowsRepeatJumps() {
    let navigation = CompactWorkoutNavigation()
    let order = ["bench", "incline", "fly", "press"]
    navigation.observeVisible(["fly", "incline"], order: order)
    #expect(navigation.visibleExerciseID == "incline")
    navigation.observeVisible([], order: order)
    navigation.jump(to: "unknown", order: order)
    #expect(navigation.visibleExerciseID == "incline")
    #expect(navigation.jumpRevision == 0)
    navigation.jump(to: "fly", order: order)
    navigation.jump(to: "fly", order: order)
    #expect(navigation.jumpRevision == 2)
    #expect(navigation.jumpExerciseID == "fly")
}

@Test @MainActor
func splitWeightDraftRoundTripsCopiesAndKeepsBothSides() {
    let session = CompactSession()
    session.edit("weight")
    session.core.setEditorSplit(true)
    #expect(session.core.editorWeightText == "30")
    #expect(session.core.editorRightWeightText == "30")
    session.core.pressEditorKey("2"); session.core.pressEditorKey("4")
    session.core.switchEditor(to: "weightRight")
    session.core.pressEditorKey("2"); session.core.pressEditorKey("6")
    session.core.setEditorSplit(false)
    #expect(session.core.editorWeightText == "50")
    session.core.setEditorSplit(true)
    #expect(session.core.editorWeightText == "24")
    #expect(session.core.editorRightWeightText == "26")
    session.core.swapEditorSides()
    #expect(session.core.editorWeightText == "26")
    session.core.matchEditorSides()
    #expect(session.core.editorRightWeightText == "26")
    session.core.copyEditorToNext()
    #expect(session.core.activeSets[3].weightRight == 26)
    #expect(session.core.activeSets[2].weightRight == nil)
    session.save(complete: true)
    #expect(session.core.activeSets[2].weight == 26)
    #expect(session.core.activeSets[2].weightRight == 26)
    #expect(session.core.totalVolume == 1_600)
    _ = session.select(exercise: "bench", setID: 3)
    session.edit("weightRight")
    #expect(session.core.editorRightWeightText == "26")
}

@Test @MainActor
func splitWeightValidationAndDiscardPreserveRecordsAndTinyTotals() {
    let session = CompactSession()
    session.edit("weight")
    session.core.applyEditorTotalWeight(0.01)
    session.core.setEditorSplit(true)
    #expect(session.core.editorWeightText == "0")
    #expect(session.core.editorRightWeightText == "0.01")
    session.core.switchEditor(to: "weightRight"); session.core.pressEditorKey("delete")
    #expect(!session.core.editorCanCommit)
    #expect(!session.select(exercise: "incline"))
    session.core.setEditorSplit(false)
    #expect(session.core.editorIsSplit)
    session.discardDraft()
    #expect(session.core.activeSets[2].weight == 60)
    #expect(session.core.activeSets[2].weightRight == nil)
}

@Test @MainActor
func machineDefaultIsSeparateFromSetDraftAndOnlySeedsNewSets() {
    let session = CompactSession()
    _ = session.select(exercise: "fly")
    session.edit("weight"); session.core.pressEditorKey("3"); session.core.pressEditorKey("0")
    session.beginEquipmentDefault()
    session.pressEquipmentDefaultKey("4"); session.pressEquipmentDefaultKey("5")
    #expect(!session.select(exercise: "bench"))
    session.saveEquipmentDefault()
    #expect(session.equipmentDefault == 45)
    #expect(session.core.editorWeightText == "30")
    #expect(session.core.activeSets[0].weight == 24)
    session.discardDraft()
    session.addSet()
    #expect(session.core.activeSets.last?.weight == 45)
    #expect(session.core.activeSets.first?.weight == 24)
    session.edit("weight"); session.core.setEditorSplit(true)
    session.core.pressEditorKey("1")
    session.applyEquipmentDefault()
    #expect(session.core.editorWeightText == "22.5")
    #expect(session.core.editorRightWeightText == "22.5")
    session.save()
    #expect(session.selectedSet?.weightRight == 22.5)
    session.beginEquipmentDefault(); session.pressEquipmentDefaultKey("9")
    session.cancelEquipmentDefault()
    #expect(session.equipmentDefault == 45)
    session.clearEquipmentDefault()
    #expect(session.equipmentDefault == nil)
    session.discardDraft()
    _ = session.select(exercise: "bench")
    #expect(session.equipmentDefault == nil)
    #expect(!session.supportsEquipmentDefault)
}

@Test @MainActor
func invalidMachineDefaultCannotReplaceSavedValue() {
    let session = CompactSession()
    _ = session.select(exercise: "fly")
    session.beginEquipmentDefault()
    for key in ["1", "0", "0", "0"] { session.pressEquipmentDefaultKey(key) }
    #expect(!session.canSaveEquipmentDefault)
    session.saveEquipmentDefault()
    #expect(session.isEditingEquipmentDefault)
    #expect(session.equipmentDefault == nil)
    session.pressEquipmentDefaultKey("delete")
    #expect(session.canSaveEquipmentDefault)
    session.saveEquipmentDefault()
    #expect(session.equipmentDefault == 100)
}

@Test @MainActor
func compactDemoStatesPreserveDraftAndRecoverFromError() {
    let session = CompactSession()
    session.edit("weight")
    session.core.pressEditorKey("7")
    session.setContentState(.loading)
    #expect(session.contentState == .loading)
    #expect(session.core.editorWeightText == "7")
    session.setContentState(.error)
    session.setContentState(.populated)
    #expect(session.contentState == .populated)
    #expect(session.core.editorWeightText == "7")
}

@Test @MainActor
func compactEquipmentDefaultAcceptsSixCharacterDecimalAndRejectsOverflow() {
    let session = CompactSession()
    _ = session.select(exercise: "fly")
    session.beginEquipmentDefault()
    for key in ["9", "9", "9", ".", "9"] { session.pressEquipmentDefaultKey(key) }
    #expect(session.equipmentDefaultText == "999.9")
    #expect(session.canSaveEquipmentDefault)
    session.pressEquipmentDefaultKey("9")
    #expect(session.equipmentDefaultText == "999.99")
    session.pressEquipmentDefaultKey("9")
    #expect(session.equipmentDefaultText == "999.99")
}

@Test @MainActor
func compactNavigationKeepsBrowseAndEditTargetsIndependent() {
    let session = CompactSession()
    session.edit("weight")
    let target = session.target
    session.navigation.observeVisible(["incline"], order: session.core.workoutIDs)
    #expect(session.navigation.visibleExerciseID == "incline")
    #expect(session.target == target)
    #expect(session.core.editorField == "weight")
}
