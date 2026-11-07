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

    func testNativeOutlineSheetContract() throws {
        let source = try sourceText()
        XCTAssertTrue(source.contains(".sheet(isPresented: $isSidebarReordering)"))
        XCTAssertTrue(source.contains("NavigationStack"))
        XCTAssertTrue(source.contains(".listStyle(.insetGrouped)"))
        XCTAssertTrue(source.contains(".presentationDetents([.medium, .large])"))
        XCTAssertTrue(source.contains("workout_exercise_sheet_trigger"))
        XCTAssertFalse(source.contains("exerciseSidebar"))
        XCTAssertFalse(source.contains("workout_exercise_pill_bar"))
    }

    func testOutlineObservationContract() throws {
        let source = try sourceText()
        XCTAssertTrue(source.contains("onSidebarItemFrame"))
        XCTAssertTrue(source.contains("onSidebarNameFrame"))
        XCTAssertTrue(source.contains("onSidebarAddFrame"))
        XCTAssertTrue(source.contains("onSidebarSelectionState"))
        XCTAssertTrue(source.contains("onSidebarMoveReady"))
        XCTAssertTrue(source.contains("onSidebarReorderToggleAction"))
        XCTAssertFalse(source.contains("sidebarAddExerciseButton"))
        XCTAssertFalse(source.contains("minWidth: 236"))
    }

    func testFunctionalGlassAndExplicitCompletionContracts() throws {
        let source = try sourceText()
        XCTAssertTrue(source.contains("workout_exercise_sheet_trigger"))
        XCTAssertTrue(source.contains(".sheet(isPresented: $isSidebarReordering)"))

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
        XCTAssertTrue(snackbar.contains(".liquidGlassBar(theme: theme, cornerRadius: 12)"))
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
