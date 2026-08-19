// MY-1446 P1-5: XCUI accessibility-tree assertion for slotEnvelope
// .accessibilityHidden contract. This is the gold-standard semantic test:
// XCUIElement queries reflect the real accessibility tree that VoiceOver
// presents to users — if an element is .accessibilityHidden, XCUI will
// report it as non-existent.
//
// Test host launches the app with `-SnackbarA11yTestMode undo|rest`
// (see VitalStrideApp.swift `#if DEBUG` block) which presents
// ActiveWorkoutSnackbarLayout.slotEnvelope full-screen with known labels.
import XCTest

private enum A11yTestTimeout {
    /// Generous wait for the test host view to render and the accessibility
    /// tree to stabilize. SwiftUI needs a layout pass + bridge update.
    static let render: TimeInterval = 5.0
}

final class SnackbarAccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Undo slot active

    /// When snackbarSlot == .undo, the undo content must be in the
    /// accessibility tree and the rest content must NOT be (hidden).
    @MainActor
    func test_undoSlot_activeContentAccessible_inactiveHidden() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SnackbarA11yTestMode", "undo"]
        app.launch()

        // The active element is also the render-ready signal. Do not first
        // depend on a SwiftUI layout container projecting as a particular
        // XCUI element type; only semantic content has a stable contract.
        let undoElement = app.staticTexts["snackbar_undo_content"]
        XCTAssertTrue(
            undoElement.waitForExistence(timeout: A11yTestTimeout.render),
            "Active undo content must be accessible (in the XCUI tree)"
        )

        // Inactive rest content must NOT be in the accessibility tree
        let restElement = app.staticTexts["snackbar_rest_content"]
        XCTAssertFalse(
            restElement.exists,
            "Inactive rest content must be accessibilityHidden (absent from XCUI tree)"
        )
    }

    // MARK: - Rest slot active

    /// When snackbarSlot == .rest, the rest content must be in the
    /// accessibility tree and the undo content must NOT be (hidden).
    @MainActor
    func test_restSlot_activeContentAccessible_inactiveHidden() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SnackbarA11yTestMode", "rest"]
        app.launch()

        // The active semantic element is the render-ready signal.
        let restElement = app.staticTexts["snackbar_rest_content"]
        XCTAssertTrue(
            restElement.waitForExistence(timeout: A11yTestTimeout.render),
            "Active rest content must be accessible (in the XCUI tree)"
        )

        // Inactive undo content must NOT be in the accessibility tree
        let undoElement = app.staticTexts["snackbar_undo_content"]
        XCTAssertFalse(
            undoElement.exists,
            "Inactive undo content must be accessibilityHidden (absent from XCUI tree)"
        )
    }
}
