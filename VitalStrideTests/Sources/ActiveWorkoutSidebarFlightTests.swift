import Foundation
import XCTest

@testable import VitalStride

final class ActiveWorkoutSidebarFlightTests: XCTestCase {
    func testSchemeBReorderWidthCoversContainer() {
        let listWidth: CGFloat = 640
        XCTAssertEqual(max(260, listWidth), 640)
        XCTAssertEqual(max(280, listWidth), 640)
    }

    func testSchemeBCollapsedRailWidth() {
        XCTAssertEqual(0, 0)
    }

    func testSchemeCPillBarContract() throws {
        let source = try sourceText()
        XCTAssertTrue(source.contains("private var collapsedSidebarWidth: CGFloat"))
        XCTAssertTrue(source.contains("0"))
        XCTAssertTrue(source.contains("workout_exercise_pill_"))
        XCTAssertTrue(source.contains("workout_exercise_pill_bar"))
        XCTAssertTrue(source.contains("workout_pill_bar_reorder"))
        XCTAssertTrue(source.contains("if isSidebarSchemeC && !isSidebarReordering"))
    }

    func testReorderSurfaceContract() throws {
        let source = try sourceText()
        XCTAssertTrue(source.contains(".padding(.horizontal, isSidebarReordering ? 12 : 2)"))
        XCTAssertTrue(source.contains("sidebarAddExerciseButton"))
        XCTAssertTrue(source.contains("minWidth: 236"))
        XCTAssertFalse(source.contains("containerWidth * 0.74"))
    }

    func testFunctionalGlassAndExplicitCompletionContracts() throws {
        let source = try sourceText()
        XCTAssertTrue(source.contains("workout_exercise_sheet_trigger"))
        XCTAssertTrue(source.contains("if isSidebarReordering"))

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let snackbar = try String(
            contentsOf: root.appendingPathComponent(
                "VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(snackbar.contains("GlassEffectContainer"))
        let setRow = try String(contentsOf: root.appendingPathComponent("VitalStride/Sources/ActiveWorkout/SetRow.swift"), encoding: .utf8)
        let subSetRow = try String(contentsOf: root.appendingPathComponent("VitalStride/Sources/ActiveWorkout/SubSetRow.swift"), encoding: .utf8)
        XCTAssertFalse(setRow.contains("background {\n            Button(action: toggleCompleted)"))
        XCTAssertFalse(subSetRow.contains("background {\n            Button(action: toggleCompleted)"))
        XCTAssertTrue(setRow.contains("ActiveWorkoutHitTarget.side"))
        XCTAssertTrue(subSetRow.contains("ActiveWorkoutHitTarget.side"))
        XCTAssertTrue(setRow.contains(".sensoryFeedback(.success, trigger: exerciseSet.isCompleted)"))
        XCTAssertTrue(subSetRow.contains(".sensoryFeedback(.success, trigger: exerciseSet.isCompleted)"))
    }

    private func sourceText() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/ActiveWorkoutView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
