import Foundation
import SwiftData
import Testing
import VitalModels
@testable import VitalStride

@Suite("Workout Logging V2")
struct WorkoutLoggingV2Tests {
    @Test("Heart-rate resolver is honest across connection and freshness states")
    func heartRateStates() {
        let now = Date()
        #expect(HeartRateStateResolver.resolve(connection: .notPaired, lastValue: 142, lastTimestamp: now, now: now) == .disconnected)
        #expect(HeartRateStateResolver.resolve(connection: .reachable, lastValue: nil, lastTimestamp: nil, now: now) == .awaiting)
        #expect(HeartRateStateResolver.resolve(connection: .reachable, lastValue: 142, lastTimestamp: now.addingTimeInterval(-2), now: now) == .value(142))
        #expect(HeartRateStateResolver.resolve(connection: .reachable, lastValue: 142, lastTimestamp: now.addingTimeInterval(-21), now: now) == .awaiting)
    }

    @Test("Numeric input replaces selection and rejects decimals for reps")
    func numericInputRules() {
        let replaced = NumericKeypadInputHandler.handleKeyPress(.digit(8), currentText: "65", selection: 0..<2, mode: .decimal)
        #expect(replaced.text == "8")
        #expect(replaced.cursor == 1)
        let integer = NumericKeypadInputHandler.handleKeyPress(.decimal, currentText: "8", selection: 1..<1, mode: .integer)
        #expect(integer.text == "8")
    }

    @Test("Set tree numbers ignore drop and pyramid children")
    func setTreeNumbering() {
        let sets = [
            ExerciseSet(order: 0, weight: 60, reps: 8, setType: .working),
            ExerciseSet(order: 1, weight: 48, reps: 8, setType: .dropSet),
            ExerciseSet(order: 2, weight: 65, reps: 8, setType: .working),
            ExerciseSet(order: 3, weight: 55, reps: 8, setType: .pyramid)
        ]
        let contexts = ActiveExerciseSection.rowContexts(from: sets)
        #expect(contexts.map(\.mainSetNumber) == [0, 0, 1, 1])
        #expect(contexts[1].isLastSubSet)
        #expect(contexts[3].isLastSubSet)
    }

    @Test("Delete arbitration gives the single undo slot priority over rest")
    func deletionArbitration() {
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: true, restPhase: .resting) == .undo)
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .resting) == .rest)
        #expect(BottomSnackbarSlot.resolve(hasPendingUndo: false, restPhase: .idle) == .none)
    }
}
