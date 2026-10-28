// swiftlint:disable no_hardcoded_chinese
import XCTest

final class ActiveWorkoutToolbarPersistenceUITests: XCTestCase {
    private let largeModeIdentifier = "active_workout_large_mode"
    private let finishIdentifier = "active_workout_finish"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testToolbarPersistsAcrossNativeRelaunchAndFinishRemainsIsolated() throws {
        let app = XCUIApplication()
        defer { app.terminate() }
        launchActiveWorkout(app)
        // Normalize through the real native action, never a launch preference override.
        if app.buttons[largeModeIdentifier].label == normalSizeAction {
            app.buttons[largeModeIdentifier].tap()
        }
        assertMode(app, large: false, stage: "initial-normal")
        app.buttons[largeModeIdentifier].tap()
        assertMode(app, large: true, stage: "toggled-large")

        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        launchActiveWorkout(app)
        assertMode(app, large: true, stage: "new-process-restored-large")
        app.buttons[largeModeIdentifier].tap()
        assertMode(app, large: false, stage: "toggled-back-normal")

        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        launchActiveWorkout(app)
        assertMode(app, large: false, stage: "new-process-restored-normal")
        app.buttons[finishIdentifier].tap()
        let confirmation = app.alerts.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        XCTAssertTrue(confirmation.staticTexts[isChinese ? "完成训练？" : "Finish workout?"].exists)
        keepScreenshot("finish-confirmation")
        confirmation.buttons[isChinese ? "取消" : "Cancel"].tap()
        XCTAssertFalse(confirmation.exists)
        XCTAssertTrue(app.buttons[largeModeIdentifier].isHittable)
        // Discard only the blank test workout through the existing confirmation path.
        app.navigationBars.buttons[isChinese ? "放弃" : "Discard"].tap()
        let discard = app.alerts.firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 10))
        discard.buttons[isChinese ? "放弃" : "Discard"].tap()
        let dismissed = NSPredicate(format: "exists == false")
        expectation(for: dismissed, evaluatedWith: app.buttons[largeModeIdentifier])
        waitForExpectations(timeout: 10)
    }

    private var isChinese: Bool { Locale.current.language.languageCode?.identifier == "zh" }
    private var normalSizeAction: String { isChinese ? "切换普通字号" : "Switch to normal text size" }
    private var largeSizeAction: String { isChinese ? "切换大字号" : "Switch to large text size" }

    @MainActor
    private func launchActiveWorkout(_ app: XCUIApplication) {
        // Existing onboarding preference, with no production fixture or mode override.
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        let workoutTab = app.tabBars.buttons[isChinese ? "训练" : "Workouts"]
        // A nonempty interrupted workout can present the existing recovery alert.
        let resume = app.alerts.buttons[isChinese ? "恢复训练" : "Resume"]
        if resume.waitForExistence(timeout: 2) {
            resume.tap()
        } else {
            XCTAssertTrue(workoutTab.waitForExistence(timeout: 15))
            workoutTab.tap()
            let start = app.navigationBars.buttons[isChinese ? "开始训练" : "Start workout"]
            XCTAssertTrue(start.waitForExistence(timeout: 10))
            start.tap()
            let blank = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", isChinese ? "空白训练" : "Blank workout")
            ).firstMatch
            XCTAssertTrue(blank.waitForExistence(timeout: 10))
            blank.tap()
        }
        XCTAssertTrue(app.buttons[largeModeIdentifier].waitForExistence(timeout: 15))
    }

    @MainActor
    private func assertMode(_ app: XCUIApplication, large: Bool, stage: String) {
        let mode = app.buttons[largeModeIdentifier]
        let finish = app.buttons[finishIdentifier]
        let expected = large ? normalSizeAction : largeSizeAction
        let correctLabel = NSPredicate(format: "label == %@", expected)
        expectation(for: correctLabel, evaluatedWith: mode)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.alerts.firstMatch.exists, "Large Mode must not request Finish")
        XCTAssertEqual(finish.label, isChinese ? "结束训练" : "Finish workout")
        XCTAssertTrue(mode.isHittable)
        XCTAssertTrue(finish.isHittable)
        XCTAssertGreaterThanOrEqual(mode.frame.width, 44 - 1e-3)
        XCTAssertGreaterThanOrEqual(mode.frame.height, 44 - 1e-3)
        XCTAssertGreaterThanOrEqual(finish.frame.width, 44 - 1e-3)
        XCTAssertGreaterThanOrEqual(finish.frame.height, 44 - 1e-3)
        XCTAssertGreaterThanOrEqual(finish.frame.minX - mode.frame.maxX, 4)
        XCTAssertEqual(app.navigationBars.buttons.matching(identifier: largeModeIdentifier).count, 1)
        XCTAssertEqual(app.navigationBars.buttons.matching(identifier: finishIdentifier).count, 1)
        let evidence = XCTAttachment(string: """
        stage=\(stage); processLocale=\(Locale.current.identifier); language=\(Locale.preferredLanguages)
        appState=\(app.state.rawValue); expectedLarge=\(large); label=\(mode.label)
        largeFrame=\(mode.frame); finishFrame=\(finish.frame); hittable=\(mode.isHittable),\(finish.isHittable)
        navigationBarMembership=true; finishAlertAbsent=true
        """)
        evidence.name = "T07 native state \(stage) \(Locale.current.identifier)"
        evidence.lifetime = .keepAlways
        add(evidence)
        keepScreenshot(stage)
    }

    @MainActor
    private func keepScreenshot(_ stage: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "T07 native \(stage) \(Locale.current.identifier)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
