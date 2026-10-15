// MY-1473 / Spec 023: Behavioral UI test for active workout whole-section reorder.
// Verified under owner decision Option A (comment eb00fa65-5302-4150-99b4-d742c9b186aa).
import XCTest

private enum ReorderTestTimeout {
    static let render: TimeInterval = 8.0
    static let interaction: TimeInterval = 4.0
}

final class ActiveWorkoutSectionReorderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_activeWorkout_reorderExerciseSections_persistsAcrossReopen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ActiveWorkoutReorderTestMode"]
        app.launch()

        // 1. Wait for active workout to render with three exercises
        let exerciseA = app.staticTexts["Exercise A"].firstMatch
        let exerciseB = app.staticTexts["Exercise B"].firstMatch
        let exerciseC = app.staticTexts["Exercise C"].firstMatch

        XCTAssertTrue(
            exerciseA.waitForExistence(timeout: ReorderTestTimeout.render),
            "Exercise A must be visible"
        )
        XCTAssertTrue(
            exerciseB.waitForExistence(timeout: ReorderTestTimeout.render),
            "Exercise B must be visible"
        )
        XCTAssertTrue(
            exerciseC.waitForExistence(timeout: ReorderTestTimeout.render),
            "Exercise C must be visible"
        )

        // Initial order: A before B, B before C
        XCTAssertLessThan(
            exerciseA.frame.minY,
            exerciseB.frame.minY,
            "Initial order: A should be above B"
        )
        XCTAssertLessThan(
            exerciseB.frame.minY,
            exerciseC.frame.minY,
            "Initial order: B should be above C"
        )

        // 2. Enter edit mode
        let editButton = app.buttons["ActiveWorkoutEditButton"]
        XCTAssertTrue(
            editButton.waitForExistence(timeout: ReorderTestTimeout.render),
            "Edit button must exist in toolbar"
        )
        editButton.tap()

        // 3. Drag the whole Exercise C section before Exercise A.
        let sourceHandle = app.images["ActiveWorkoutExerciseMoveHandle_Exercise C"]
        let targetHandle = app.images["ActiveWorkoutExerciseMoveHandle_Exercise A"]
        XCTAssertTrue(
            sourceHandle.waitForExistence(timeout: ReorderTestTimeout.render),
            "Exercise C section drag handle must exist in edit mode"
        )
        XCTAssertTrue(
            targetHandle.waitForExistence(timeout: ReorderTestTimeout.render),
            "Exercise A section drop target must exist in edit mode"
        )
        XCTAssertEqual(sourceHandle.label, "Exercise C")
        XCTAssertGreaterThanOrEqual(sourceHandle.frame.width, 44)
        XCTAssertGreaterThanOrEqual(sourceHandle.frame.height, 44)

        // Existing main-set and sub-set edit/delete controls remain independently focusable.
        let mainSetMenu = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '设置'")
        ).firstMatch
        let subSetDeleteMenu = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '子组操作菜单'")
        ).firstMatch
        XCTAssertTrue(
            mainSetMenu.waitForExistence(timeout: ReorderTestTimeout.render),
            "Main-set configuration control must remain available in edit mode"
        )
        XCTAssertTrue(
            subSetDeleteMenu.waitForExistence(timeout: ReorderTestTimeout.render),
            "Sub-set delete menu must remain available in edit mode"
        )
        XCTAssertGreaterThanOrEqual(mainSetMenu.frame.width, 44)
        XCTAssertGreaterThanOrEqual(mainSetMenu.frame.height, 44)
        XCTAssertGreaterThanOrEqual(subSetDeleteMenu.frame.width, 44)
        XCTAssertGreaterThanOrEqual(subSetDeleteMenu.frame.height, 44)

        sourceHandle.press(forDuration: 0.8, thenDragTo: targetHandle)

        // 4. Assert immediate C, A, B order
        let updatedA = app.staticTexts["Exercise A"].firstMatch
        let updatedB = app.staticTexts["Exercise B"].firstMatch
        let updatedC = app.staticTexts["Exercise C"].firstMatch

        XCTAssertLessThan(
            updatedC.frame.minY,
            updatedA.frame.minY,
            "Immediate order: C should be above A after reorder"
        )
        XCTAssertLessThan(
            updatedA.frame.minY,
            updatedB.frame.minY,
            "Immediate order: A should be above B after reorder"
        )

        // 5. Exit edit mode
        let doneButton = app.buttons["ActiveWorkoutEditButton"]
        XCTAssertTrue(
            doneButton.waitForExistence(timeout: ReorderTestTimeout.interaction),
            "Done button must remain available after reordering"
        )
        doneButton.tap()

        // 6. Leave and re-enter hosted workout to verify persistence
        let leaveButton = app.buttons["ActiveWorkoutTestLeaveButton"]
        XCTAssertTrue(
            leaveButton.waitForExistence(timeout: ReorderTestTimeout.interaction),
            "Leave control must exist for persistence verification"
        )
        leaveButton.tap()

        let reopenButton = app.buttons["ActiveWorkoutTestReopenButton"]
        XCTAssertTrue(
            reopenButton.waitForExistence(timeout: ReorderTestTimeout.interaction),
            "Reopen button must appear after leaving workout"
        )
        reopenButton.tap()

        // 7. Verify reopened C, A, B order
        let reopenedA = app.staticTexts["Exercise A"].firstMatch
        let reopenedB = app.staticTexts["Exercise B"].firstMatch
        let reopenedC = app.staticTexts["Exercise C"].firstMatch

        XCTAssertTrue(
            reopenedC.waitForExistence(timeout: ReorderTestTimeout.render),
            "Exercise C must be visible after reopening"
        )

        XCTAssertLessThan(
            reopenedC.frame.minY,
            reopenedA.frame.minY,
            "Persisted order: C should be above A after reopening"
        )
        XCTAssertLessThan(
            reopenedA.frame.minY,
            reopenedB.frame.minY,
            "Persisted order: A should be above B after reopening"
        )

        // 8. Large Mode retains the same contextual 44pt whole-section drag control.
        let largeModeButton = app.buttons["ActiveWorkoutLargeModeButton"]
        XCTAssertTrue(
            largeModeButton.waitForExistence(timeout: ReorderTestTimeout.interaction),
            "Large Mode toggle must exist"
        )
        XCTAssertFalse(
            largeModeButton.label.isEmpty,
            "Large Mode toggle must retain its localized spoken label"
        )
        largeModeButton.tap()

        let reopenedEditButton = app.buttons["ActiveWorkoutEditButton"]
        XCTAssertTrue(
            reopenedEditButton.waitForExistence(timeout: ReorderTestTimeout.interaction),
            "Edit button must exist in Large Mode"
        )
        reopenedEditButton.tap()

        let largeSourceHandle = app.images["ActiveWorkoutExerciseMoveHandle_Exercise B"]
        let largeTargetHandle = app.images["ActiveWorkoutExerciseMoveHandle_Exercise C"]
        XCTAssertTrue(
            largeSourceHandle.waitForExistence(timeout: ReorderTestTimeout.render),
            "Exercise B drag handle must exist in Large Mode"
        )
        XCTAssertTrue(
            largeTargetHandle.waitForExistence(timeout: ReorderTestTimeout.render),
            "Exercise C drop target must exist in Large Mode"
        )
        XCTAssertEqual(largeSourceHandle.label, "Exercise B")
        XCTAssertGreaterThanOrEqual(largeSourceHandle.frame.width, 44)
        XCTAssertGreaterThanOrEqual(largeSourceHandle.frame.height, 44)
        largeSourceHandle.press(forDuration: 0.8, thenDragTo: largeTargetHandle)

        let largeB = app.staticTexts["Exercise B"].firstMatch
        let largeC = app.staticTexts["Exercise C"].firstMatch
        XCTAssertLessThan(
            largeB.frame.minY,
            largeC.frame.minY,
            "Large Mode drag must move the whole Exercise B section before Exercise C"
        )
    }
}
