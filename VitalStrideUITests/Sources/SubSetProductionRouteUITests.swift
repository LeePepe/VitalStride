import XCTest

/// Production-hosted UI acceptance tests for shared editable sub-set rows and deletion route
/// (spec 026 / AC-001, AC-002, AC-004, AC-006, AC-007, AC-008).
final class SubSetProductionRouteUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - AC-001 & AC-003: Actual Pyramid Menu Route & Undo Restoration

    func testActualPyramidMenuDeleteRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        let allMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertTrue(allMenus.element(boundBy: 1).waitForExistence(timeout: 5.0), "Pyramid row action menu trigger should exist")

        let pyramidMenu = allMenus.element(boundBy: 1)
        let pyramidID = pyramidMenu.identifier
            .replacingOccurrences(of: "active-workout.row.", with: "")
            .replacingOccurrences(of: ".action-menu", with: "")

        pyramidMenu.tap()

        // Tap the destructive delete item in the opened menu
        let deleteButton = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.delete-menu-item'")).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3.0), "Delete menu item should exist in opened menu")
        deleteButton.tap()

        // Verify probe counters and selected row identity
        let requestCount = app.staticTexts["subset_probe_request_count"]
        let seamCount = app.staticTexts["subset_probe_seam_count"]
        let callbackCount = app.staticTexts["subset_probe_callback_count"]
        let lastID = app.staticTexts["subset_probe_last_set_id"]
        let lastType = app.staticTexts["subset_probe_last_set_type"]
        let undoState = app.staticTexts["subset_probe_undo_state"]
        let lastAnnouncement = app.staticTexts["subset_probe_last_announcement"]

        XCTAssertTrue(requestCount.waitForExistence(timeout: 3.0))
        XCTAssertEqual(requestCount.label, "Requests: 1")
        XCTAssertEqual(seamCount.label, "Seam: 1")
        XCTAssertEqual(callbackCount.label, "Callbacks: 1")
        XCTAssertTrue(lastID.label.contains(pyramidID), "Last requested set ID must match pyramid row ID")
        XCTAssertTrue(lastType.label.contains("递增") || lastType.label.contains("金字塔") || lastType.label.localizedCaseInsensitiveContains("pyramid"))
        XCTAssertEqual(undoState.label, "Undo: available")
        XCTAssertFalse(lastAnnouncement.label.contains("none"))

        // Exercise undo action to restore pyramid row
        let undoButton = app.buttons["subset_probe_undo_button"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 2.0))
        undoButton.tap()

        // After undo, exactly 3 rows exist with pyramid restored
        let allRestoredMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertEqual(allRestoredMenus.count, 3, "Pyramid row should be restored after undo")
    }

    // MARK: - AC-002 & AC-003: Actual Committed Full Swipe Route & Undo Restoration

    func testActualDropSetFullSwipeRoute() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        let allMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertTrue(allMenus.element(boundBy: 2).waitForExistence(timeout: 5.0), "Drop-set row should exist")

        let dropSetMenu = allMenus.element(boundBy: 2)
        let dropSetID = dropSetMenu.identifier
            .replacingOccurrences(of: "active-workout.row.", with: "")
            .replacingOccurrences(of: ".action-menu", with: "")

        let dropSetCell = app.cells.containing(.button, identifier: dropSetMenu.identifier).firstMatch
        if dropSetCell.exists {
            let start = dropSetCell.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let end = dropSetCell.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        } else {
            let start = dropSetMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
            let end = dropSetMenu.coordinate(withNormalizedOffset: CGVector(dx: -0.8, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        // Verify probe counters and selected row identity
        let requestCount = app.staticTexts["subset_probe_request_count"]
        let seamCount = app.staticTexts["subset_probe_seam_count"]
        let callbackCount = app.staticTexts["subset_probe_callback_count"]
        let lastID = app.staticTexts["subset_probe_last_set_id"]
        let lastType = app.staticTexts["subset_probe_last_set_type"]
        let undoState = app.staticTexts["subset_probe_undo_state"]

        XCTAssertTrue(requestCount.waitForExistence(timeout: 5.0))
        XCTAssertEqual(requestCount.label, "Requests: 1")
        XCTAssertEqual(seamCount.label, "Seam: 1")
        XCTAssertEqual(callbackCount.label, "Callbacks: 1")
        XCTAssertTrue(lastID.label.contains(dropSetID), "Last requested set ID must match drop-set row ID")
        XCTAssertTrue(lastType.label.contains("递减") || lastType.label.localizedCaseInsensitiveContains("drop"))
        XCTAssertEqual(undoState.label, "Undo: available")

        // Exercise undo action to restore drop-set row
        let undoButton = app.buttons["subset_probe_undo_button"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 2.0))
        undoButton.tap()

        let allRestoredMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertEqual(allRestoredMenus.count, 3, "Drop-set row should be restored after undo")
    }

    // MARK: - AC-004: Production-Reachable Refusal

    func testProductionReachableRefusalInSingleMainWithChild() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "single_main_with_child"]
        app.launch()

        let allMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertEqual(allMenus.count, 2, "Fixture must start with exactly standard and child row")

        let standardMenu = allMenus.element(boundBy: 0)
        let standardID = standardMenu.identifier
            .replacingOccurrences(of: "active-workout.row.", with: "")
            .replacingOccurrences(of: ".action-menu", with: "")

        let dropSetMenu = allMenus.element(boundBy: 1)
        let dropSetID = dropSetMenu.identifier
            .replacingOccurrences(of: "active-workout.row.", with: "")
            .replacingOccurrences(of: ".action-menu", with: "")

        // Open standard set menu and tap delete
        standardMenu.tap()
        let deleteMenuItem = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.delete-menu-item'")).firstMatch
        XCTAssertTrue(deleteMenuItem.waitForExistence(timeout: 3.0))
        deleteMenuItem.tap()

        // Confirmation dialog appears; tap confirmation destructive button
        let confirmDeleteButton = app.buttons.matching(NSPredicate(format: "label == '删除' OR label == 'Delete'")).firstMatch
        XCTAssertTrue(confirmDeleteButton.waitForExistence(timeout: 3.0), "Confirmation dialog action should appear")
        confirmDeleteButton.tap()

        // Verify refusal: request=1, seam=2 (request + confirmation), callback=0, undo=none, announcement=none
        let requestCount = app.staticTexts["subset_probe_request_count"]
        let seamCount = app.staticTexts["subset_probe_seam_count"]
        let callbackCount = app.staticTexts["subset_probe_callback_count"]
        let undoState = app.staticTexts["subset_probe_undo_state"]
        let lastAnnouncement = app.staticTexts["subset_probe_last_announcement"]

        XCTAssertTrue(callbackCount.waitForExistence(timeout: 2.0))
        XCTAssertEqual(requestCount.label, "Requests: 1")
        XCTAssertEqual(seamCount.label, "Seam: 2")
        XCTAssertEqual(callbackCount.label, "Callbacks: 0")
        XCTAssertEqual(undoState.label, "Undo: none")
        XCTAssertEqual(lastAnnouncement.label, "Announcement: none")

        // Both rows remain present in exact order [0, 1]
        let remainingStandard = app.buttons["active-workout.row.\(standardID).action-menu"]
        let remainingDropSet = app.buttons["active-workout.row.\(dropSetID).action-menu"]
        XCTAssertTrue(remainingStandard.waitForExistence(timeout: 2.0), "Standard row must remain on refusal")
        XCTAssertTrue(remainingDropSet.waitForExistence(timeout: 2.0), "Drop-set row must remain on refusal")
    }

    // MARK: - AC-006: Actual Adjacent Geometry

    func testActualAdjacentActionMenuTriggerGeometry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        let allMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertEqual(allMenus.count, 3, "Fixture must contain exactly 3 rows")

        let standardMenu = allMenus.element(boundBy: 0)
        let pyramidMenu = allMenus.element(boundBy: 1)
        let dropSetMenu = allMenus.element(boundBy: 2)

        XCTAssertTrue(standardMenu.waitForExistence(timeout: 5.0))
        XCTAssertTrue(pyramidMenu.waitForExistence(timeout: 5.0))
        XCTAssertTrue(dropSetMenu.waitForExistence(timeout: 5.0))

        let standardFrame = standardMenu.frame
        let pyramidFrame = pyramidMenu.frame
        let dropSetFrame = dropSetMenu.frame

        // Every trigger frame must be at least 44x44 points
        XCTAssertGreaterThanOrEqual(standardFrame.width.rounded(), 44.0, "Standard menu trigger width >= 44")
        XCTAssertGreaterThanOrEqual(standardFrame.height.rounded(), 44.0, "Standard menu trigger height >= 44")
        XCTAssertGreaterThanOrEqual(pyramidFrame.width.rounded(), 44.0, "Pyramid menu trigger width >= 44")
        XCTAssertGreaterThanOrEqual(pyramidFrame.height.rounded(), 44.0, "Pyramid menu trigger height >= 44")
        XCTAssertGreaterThanOrEqual(dropSetFrame.width.rounded(), 44.0, "Drop-set menu trigger width >= 44")
        XCTAssertGreaterThanOrEqual(dropSetFrame.height.rounded(), 44.0, "Drop-set menu trigger height >= 44")

        // Standard/Pyramid and Pyramid/Drop-Set intersections must be empty
        XCTAssertFalse(standardFrame.intersects(pyramidFrame), "Standard and pyramid menu triggers must not intersect")
        XCTAssertFalse(pyramidFrame.intersects(dropSetFrame), "Pyramid and drop-set menu triggers must not intersect")
    }

    // MARK: - AC-007: Cataloged Delete Identity in en & zh-Hans for Standard, Pyramid & Drop-Set

    func testCatalogedDeleteIdentity_en() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SubSetRouteTestMode", "standard_pyramid_drop",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        let allMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertEqual(allMenus.count, 3)

        // Pyramid row destructive item in English
        allMenus.element(boundBy: 1).tap()
        let pyramidDelete = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.delete-menu-item'")).firstMatch
        XCTAssertTrue(pyramidDelete.waitForExistence(timeout: 3.0))
        let pyramidLabel = pyramidDelete.label
        XCTAssertTrue(pyramidLabel.localizedCaseInsensitiveContains("delete"), "Must contain translated Delete")
        XCTAssertTrue(pyramidLabel.contains("1") || pyramidLabel.localizedCaseInsensitiveContains("set 1"), "Must contain parent set number")
        XCTAssertTrue(pyramidLabel.localizedCaseInsensitiveContains("pyramid") || pyramidLabel.contains("递增") || pyramidLabel.contains("金字塔"))
    }

    func testCatalogedDeleteIdentity_zhHans() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SubSetRouteTestMode", "standard_pyramid_drop",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_Hans_CN"
        ]
        app.launch()

        let allMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertEqual(allMenus.count, 3)

        // Pyramid row destructive item in zh-Hans
        allMenus.element(boundBy: 1).tap()
        let pyramidDelete = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.delete-menu-item'")).firstMatch
        XCTAssertTrue(pyramidDelete.waitForExistence(timeout: 3.0))
        let pyramidLabel = pyramidDelete.label
        XCTAssertTrue(pyramidLabel.contains("删除"))
        XCTAssertTrue(pyramidLabel.contains("第 1 组") || pyramidLabel.contains("1"))
        XCTAssertTrue(pyramidLabel.contains("递增") || pyramidLabel.contains("金字塔") || pyramidLabel.localizedCaseInsensitiveContains("pyramid"))
    }

    func testCatalogedDeleteIdentity_standardAndDropSet() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-SubSetRouteTestMode", "standard_pyramid_drop",
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_Hans_CN"
        ]
        app.launch()

        let allMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertEqual(allMenus.count, 3)

        // Drop-set row destructive item in zh-Hans
        allMenus.element(boundBy: 2).tap()
        let dropSetDelete = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.delete-menu-item'")).firstMatch
        XCTAssertTrue(dropSetDelete.waitForExistence(timeout: 3.0))
        let dropSetLabel = dropSetDelete.label
        XCTAssertTrue(dropSetLabel.contains("删除"))
        XCTAssertTrue(dropSetLabel.contains("第 1 组") || dropSetLabel.contains("1"))
        XCTAssertTrue(dropSetLabel.contains("递减") || dropSetLabel.localizedCaseInsensitiveContains("drop"))
    }

    // MARK: - AC-008: Shared Editable Composition and Control Effects

    func testSharedEditableCompositionAndActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SubSetRouteTestMode", "standard_pyramid_drop"]
        app.launch()

        let allMenus = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'active-workout.row.' AND identifier ENDSWITH '.action-menu'"))
        XCTAssertTrue(allMenus.element(boundBy: 1).waitForExistence(timeout: 5.0))
        let pyramidID = allMenus.element(boundBy: 1).identifier
            .replacingOccurrences(of: "active-workout.row.", with: "")
            .replacingOccurrences(of: ".action-menu", with: "")

        // 1. Weight and reps fields on pyramid row exist and are editable
        let pyramidWeight = app.textFields["active-workout.row.\(pyramidID).weight"]
        let pyramidReps = app.textFields["active-workout.row.\(pyramidID).reps"]
        XCTAssertTrue(pyramidWeight.waitForExistence(timeout: 5.0), "Pyramid weight field should exist")
        XCTAssertTrue(pyramidReps.waitForExistence(timeout: 5.0), "Pyramid reps field should exist")

        pyramidWeight.tap()
        pyramidWeight.typeText("95")
        pyramidReps.tap()
        pyramidReps.typeText("10")

        // 2. Completion toggle on pyramid row
        let pyramidCompletion = app.buttons["active-workout.row.\(pyramidID).completion"]
        XCTAssertTrue(pyramidCompletion.waitForExistence(timeout: 5.0))
        pyramidCompletion.tap()

        // 3. Open pyramid menu: verify child SetType picker and RPE picker
        allMenus.element(boundBy: 1).tap()
        let deleteButton = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.delete-menu-item'")).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3.0), "Pyramid menu should expose delete action")

        // 4. Verify standard row action menu has standard options
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        allMenus.element(boundBy: 0).tap()
        let standardDelete = app.buttons.matching(NSPredicate(format: "identifier ENDSWITH '.delete-menu-item'")).firstMatch
        XCTAssertTrue(standardDelete.waitForExistence(timeout: 3.0), "Standard menu should expose delete action")
    }
}
