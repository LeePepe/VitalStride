// swiftlint:disable no_hardcoded_chinese
import XCTest

final class ActiveWorkoutToolbarPersistenceUITests: XCTestCase {
    private let largeModeIdentifier = "active_workout_large_mode"
    private let finishIdentifier = "active_workout_finish"

    func testToolbarPersistsAcrossNativeRelaunchAndFinishRemainsIsolated() {
        let app = launchActiveWorkout()
        defer { restoreNormalModeAndTerminate(app) }

        let initialLargeMode = app.buttons[largeModeIdentifier]
        let initialFinish = app.buttons[finishIdentifier]
        assertToolbarGeometry(largeMode: initialLargeMode, finish: initialFinish)
        let initialLabel = initialLargeMode.label
        let initialScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        initialScreenshot.name = "T07 native toolbar initial \(localeIdentifier)"
        initialScreenshot.lifetime = .keepAlways
        add(initialScreenshot)

        initialLargeMode.tap()
        let toggledLargeMode = app.buttons[largeModeIdentifier]
        XCTAssertTrue(toggledLargeMode.waitForExistence(timeout: 5))
        XCTAssertNotEqual(toggledLargeMode.label, initialLabel)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let toggledScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        toggledScreenshot.name = "T07 native toolbar toggled \(localeIdentifier)"
        toggledScreenshot.lifetime = .keepAlways
        add(toggledScreenshot)

        app.terminate()
        let restored = launchActiveWorkout()
        let restoredLargeMode = restored.buttons[largeModeIdentifier]
        XCTAssertTrue(restoredLargeMode.waitForExistence(timeout: 5))
        XCTAssertEqual(restoredLargeMode.label, toggledLargeMode.label)
        assertToolbarGeometry(
            largeMode: restoredLargeMode,
            finish: restored.buttons[finishIdentifier]
        )

        restoredLargeMode.tap()
        let toggledBack = restored.buttons[largeModeIdentifier]
        XCTAssertTrue(toggledBack.waitForExistence(timeout: 5))
        XCTAssertEqual(toggledBack.label, initialLabel)
        XCTAssertFalse(restored.alerts.firstMatch.exists)

        let finish = restored.buttons[finishIdentifier]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()
        let confirmation = restored.alerts.firstMatch
        XCTAssertTrue(
            confirmation.waitForExistence(timeout: 5),
            "Finish must present the existing confirmation alert"
        )
        let finishScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        finishScreenshot.name = "T07 native toolbar finish confirmation \(localeIdentifier)"
        finishScreenshot.lifetime = .keepAlways
        add(finishScreenshot)
        confirmation.buttons.firstMatch.tap()
        XCTAssertFalse(confirmation.exists)
        restored.terminate()
    }

    private var localeIdentifier: String {
        Locale.current.identifier
    }

    private func launchActiveWorkout() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        dismissOnboardingIfNeeded(app)

        let start = firstExisting(
            in: app,
            candidates: ["Start Workout", "开始训练"],
            timeout: 10
        )
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let blank = firstExisting(
            in: app,
            candidates: ["Blank Workout", "空白训练"],
            timeout: 10
        )
        XCTAssertTrue(blank.waitForExistence(timeout: 10))
        blank.tap()
        XCTAssertTrue(app.buttons[largeModeIdentifier].waitForExistence(timeout: 10))
        return app
    }

    private func dismissOnboardingIfNeeded(_ app: XCUIApplication) {
        for label in ["Skip", "跳过", "Later", "稍后再说"] {
            let button = app.buttons[label]
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return
            }
        }
    }

    private func firstExisting(
        in app: XCUIApplication,
        candidates: [String],
        timeout: TimeInterval
    ) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for candidate in candidates {
                let element = app.buttons[candidate]
                if element.exists {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return app.buttons[candidates[0]]
    }

    private func assertToolbarGeometry(
        largeMode: XCUIElement,
        finish: XCUIElement
    ) {
        XCTAssertTrue(largeMode.waitForExistence(timeout: 5))
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        XCTAssertTrue(largeMode.isHittable)
        XCTAssertTrue(finish.isHittable)
        XCTAssertGreaterThanOrEqual(largeMode.frame.width, 44 - 1e-3)
        XCTAssertGreaterThanOrEqual(largeMode.frame.height, 44 - 1e-3)
        XCTAssertGreaterThanOrEqual(finish.frame.width, 44 - 1e-3)
        XCTAssertGreaterThanOrEqual(finish.frame.height, 44 - 1e-3)
        XCTAssertGreaterThanOrEqual(finish.frame.minX - largeMode.frame.maxX, 4)
    }

    private func restoreNormalModeAndTerminate(_ app: XCUIApplication) {
        var app = app
        if app.state == .notRunning {
            app = launchActiveWorkout()
        }
        let largeMode = app.buttons[largeModeIdentifier]
        if largeMode.waitForExistence(timeout: 5),
           (largeMode.label.localizedCaseInsensitiveContains("normal") ||
            largeMode.label.contains("普通")) {
            largeMode.tap()
        }
        app.terminate()
    }
}
