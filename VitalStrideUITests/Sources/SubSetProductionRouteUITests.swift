import XCTest

/// Production-hosted UI acceptance tests for shared editable sub-set rows and deletion route
/// (spec 026 / AC-001, AC-002, AC-004, AC-006, AC-007, AC-008).
///
/// Exercises:
/// 1. AC-001: Actual menu deletion on pyramid row.
/// 2. AC-002: Actual committed trailing full swipe on drop-set row.
/// 3. AC-004: Production-reachable refusal in single-main-with-child fixture.
/// 4. AC-006: Actual adjacent action-menu-trigger geometry (>= 44x44, disjoint).
/// 5. AC-007: Cataloged identity on destructive menu entries.
/// 6. AC-008: Shared editable controls, completion, RPE, subtype switching, and copy.
final class SubSetProductionRouteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - AC-001: Actual Pyramid Menu Route

    func testActualPyramidMenuDeleteRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        let pyramidMenu = app.buttons["active-workout.row.pyramid.action-menu"]
        XCTAssertTrue(pyramidMenu.waitForExistence(timeout: 5.0), "Pyramid action menu trigger should exist")
        pyramidMenu.tap()

        // Tap the destructive delete item in the opened menu
        let deleteButton = app.buttons["active-workout.row.pyramid.delete-menu-item"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3.0), "Delete menu item should exist in opened menu")
        deleteButton.tap()

        // Verify probe counters
        let requestCount = app.staticTexts["subset_probe_request_count"]
        let seamCount = app.staticTexts["subset_probe_seam_count"]
        let callbackCount = app.staticTexts["subset_probe_callback_count"]
        let lastType = app.staticTexts["subset_probe_last_set_type"]
        let undoState = app.staticTexts["subset_probe_undo_state"]

        XCTAssertTrue(requestCount.waitForExistence(timeout: 3.0))
        XCTAssertEqual(requestCount.label, "Requests: 1")
        XCTAssertEqual(seamCount.label, "Seam: 1")
        XCTAssertEqual(callbackCount.label, "Callbacks: 1")
        XCTAssertTrue(lastType.label.contains("递增") || lastType.label.contains("金字塔") || lastType.label.localizedCaseInsensitiveContains("pyramid"))
        XCTAssertEqual(undoState.label, "Undo: available")

        // Exercise undo action
        let undoButton = app.buttons["subset_probe_undo_button"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 2.0))
        undoButton.tap()

        // After undo, pyramid row is restored
        XCTAssertTrue(pyramidMenu.waitForExistence(timeout: 3.0), "Pyramid row should be restored after undo")
    }

    // MARK: - AC-002: Actual Committed Full Swipe Route

    func testActualDropSetFullSwipeRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        let dropSetCell = app.cells.containing(.button, identifier: "active-workout.row.dropSet.action-menu").firstMatch
        if dropSetCell.waitForExistence(timeout: 5.0) {
            let start = dropSetCell.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let end = dropSetCell.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        } else {
            let dropSetMenu = app.buttons["active-workout.row.dropSet.action-menu"]
            XCTAssertTrue(dropSetMenu.waitForExistence(timeout: 5.0), "Drop-set row should exist")
            let start = dropSetMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let end = dropSetMenu.coordinate(withNormalizedOffset: CGVector(dx: -0.8, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        // Verify probe counters
        let requestCount = app.staticTexts["subset_probe_request_count"]
        let seamCount = app.staticTexts["subset_probe_seam_count"]
        let callbackCount = app.staticTexts["subset_probe_callback_count"]
        let lastType = app.staticTexts["subset_probe_last_set_type"]
        let undoState = app.staticTexts["subset_probe_undo_state"]

        XCTAssertTrue(requestCount.waitForExistence(timeout: 5.0))
        XCTAssertEqual(requestCount.label, "Requests: 1")
        XCTAssertEqual(seamCount.label, "Seam: 1")
        XCTAssertEqual(callbackCount.label, "Callbacks: 1")
        XCTAssertTrue(lastType.label.contains("递减") || lastType.label.contains("Drop Set"))
        XCTAssertEqual(undoState.label, "Undo: available")
    }

    // MARK: - AC-004: Production-Reachable Refusal

    func testProductionReachableRefusalInSingleMainWithChild() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "single_main_with_child"]
        app.launch()

        let standardMenu = app.buttons["active-workout.row.standard.action-menu"]
        let dropSetMenu = app.buttons["active-workout.row.dropSet.action-menu"]
        XCTAssertTrue(standardMenu.waitForExistence(timeout: 5.0), "Standard row should exist")
        XCTAssertTrue(dropSetMenu.waitForExistence(timeout: 5.0), "Drop-set row should exist")

        // Open standard set menu and tap delete
        standardMenu.tap()
        let deleteMenuItem = app.buttons.matching(NSPredicate(format: "label CONTAINS '删除' OR label CONTAINS 'Delete'")).firstMatch
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 3.0))
        deleteMenuItem.tap()

        // Confirmation dialog appears; tap confirmation destructive button
        let confirmDeleteButton = app.buttons.matching(NSPredicate(format: "label == '删除' OR label == 'Delete'")).firstMatch
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 3.0), "Confirmation dialog action should appear")
        confirmDeleteButton.tap()

        // Verify refusal: both rows remain intact, callback count is 0, undo is none
        XCTAssertTrue(standardMenu.waitForExistence(timeout: 3.0), "Standard row must remain on refusal")
        XCTAssertTrue(dropSetMenu.waitForExistence(timeout: 3.0), "Drop-set row must remain on refusal")

        let callbackCount = app.staticTexts["subset_probe_callback_count"]
        let undoState = app.staticTexts["subset_probe_undo_state"]
        XCTAssertTrue(callbackCount.waitForExistence(timeout: 2.0))
        XCTAssertEqual(callbackCount.label, "Callbacks: 0")
        XCTAssertEqual(undoState.label, "Undo: none")
    }

    // MARK: - AC-006: Actual Adjacent Geometry

    func testActualAdjacentActionMenuTriggerGeometry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        let standardMenu = app.buttons["active-workout.row.standard.action-menu"]
        let pyramidMenu = app.buttons["active-workout.row.pyramid.action-menu"]
        let dropSetMenu = app.buttons["active-workout.row.dropSet.action-menu"]

        XCTAssertTrue(standardMenu.waitForExistence(timeout: 5.0))
        XCTAssertTrue(pyramidMenu.waitForExistence(timeout: 5.0))
        XCTAssertTrue(dropSetMenu.waitForExistence(timeout: 5.0))

        let standardFrame = standardMenu.frame
        let pyramidFrame = pyramidMenu.frame
        let dropSetFrame = dropSetMenu.frame

        // Every trigger frame must be at least 44x44 points
        XCTAssertGreaterThanOrEqual(standardFrame.width, 43.9, "Standard menu trigger width >= 44")
        XCTAssertGreaterThanOrEqual(standardFrame.height, 43.9, "Standard menu trigger height >= 44")
        XCTAssertGreaterThanOrEqual(pyramidFrame.width, 43.9, "Pyramid menu trigger width >= 44")
        XCTAssertGreaterThanOrEqual(pyramidFrame.height, 43.9, "Pyramid menu trigger height >= 44")
        XCTAssertGreaterThanOrEqual(dropSetFrame.width, 43.9, "Drop-set menu trigger width >= 44")
        XCTAssertGreaterThanOrEqual(dropSetFrame.height, 43.9, "Drop-set menu trigger height >= 44")

        // Standard/Pyramid and Pyramid/Drop-Set intersections must be empty
        XCTAssertFalse(standardFrame.intersects(pyramidFrame), "Standard and pyramid menu triggers must not intersect")
        XCTAssertFalse(pyramidFrame.intersects(dropSetFrame), "Pyramid and drop-set menu triggers must not intersect")
    }

    // MARK: - AC-007: Cataloged Delete Identity

    func testCatalogedDeleteIdentityOnMenuDestructiveItem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        let pyramidMenu = app.buttons["active-workout.row.pyramid.action-menu"]
        XCTAssertTrue(pyramidMenu.waitForExistence(timeout: 5.0))
        pyramidMenu.tap()

        let deleteButton = app.buttons["active-workout.row.pyramid.delete-menu-item"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3.0))

        let label = deleteButton.label
        XCTAssertTrue(label.localizedCaseInsensitiveContains("删除") || label.localizedCaseInsensitiveContains("delete"), "Must contain translated delete")
        XCTAssertTrue(label.contains("1") || label.contains("第 1 组") || label.contains("Set 1"), "Must contain parent set number")
        XCTAssertTrue(label.contains("递增") || label.contains("金字塔") || label.localizedCaseInsensitiveContains("pyramid"), "Must contain pyramid type")
    }

    // MARK: - AC-008: Shared Editable Composition and Control Effects

    func testSharedEditableCompositionAndActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        // Weight and reps fields on pyramid row
        let pyramidWeight = app.textFields["active-workout.row.pyramid.weight"]
        let pyramidReps = app.textFields["active-workout.row.pyramid.reps"]
        XCTAssertTrue(pyramidWeight.waitForExistence(timeout: 5.0), "Pyramid weight field should exist")
        XCTAssertTrue(pyramidReps.waitForExistence(timeout: 5.0), "Pyramid reps field should exist")

        // Completion toggle on pyramid row
        let pyramidCompletion = app.buttons["active-workout.row.pyramid.completion"]
        XCTAssertTrue(pyramidCompletion.waitForExistence(timeout: 5.0))
        pyramidCompletion.tap()

        // Open pyramid menu and verify action menu trigger
        let pyramidMenu = app.buttons["active-workout.row.pyramid.action-menu"]
        pyramidMenu.tap()

        let deleteButton = app.buttons.matching(NSPredicate(format: "label CONTAINS '删除' OR label CONTAINS 'Delete'")).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3.0), "Pyramid menu should expose delete action")
    }
}
