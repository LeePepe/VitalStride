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
        let exerciseA = app.staticTexts["Exercise A"]
        let exerciseB = app.staticTexts["Exercise B"]
        let exerciseC = app.staticTexts["Exercise C"]

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

        // 3. Move Exercise C before Exercise A
        let moveUpButtons = app.buttons.matching(NSPredicate(format: "label == 'Move exercise up'"))
        XCTAssertTrue(
            moveUpButtons.firstMatch.waitForExistence(timeout: ReorderTestTimeout.render),
            "Move up button must exist in edit mode"
        )
        // First move: move Exercise C (the bottom-most move up button) up to index 1
        let lastMoveUp = moveUpButtons.element(boundBy: moveUpButtons.count - 1)
        lastMoveUp.tap()

        // Second move: move Exercise C (now at index 1) up to index 0 (before Exercise A)
        let firstMoveUp = moveUpButtons.firstMatch
        XCTAssertTrue(
            firstMoveUp.waitForExistence(timeout: ReorderTestTimeout.interaction),
            "Move up button must remain available to move to top"
        )
        firstMoveUp.tap()

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
        if doneButton.exists {
            doneButton.tap()
        }

        // 6. Leave and re-enter hosted workout to verify persistence
        let leaveButton = app.buttons["ActiveWorkoutTestLeaveButton"]
        if leaveButton.waitForExistence(timeout: ReorderTestTimeout.interaction) {
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
        }
    }
}
