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
