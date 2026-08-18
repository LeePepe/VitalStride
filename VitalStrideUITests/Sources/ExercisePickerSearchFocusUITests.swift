// swiftlint:disable no_hardcoded_chinese
// spec 020 (MY-1368/MY-1370): XCUITest suite guarding the ExercisePicker
// search-field focus state against debounced content changes and @Query
// refresh. The 5 tests (T1-T5) implement spec §4.1. T6 (MY-1418/MY-1419)
// extends the same contract to zero-result transitions. Test host launches the
// app with `-ExercisePickerTestMode single|multi` (see VitalStrideApp.swift
// `#if DEBUG` block) so the picker is presented as a modal sheet without
// requiring onboarding to complete.
import XCTest

// MARK: - Timeout Constants
// XCUITest predicate waits return immediately once satisfied — a generous
// budget does NOT slow down green runs, it only prevents false-red on loaded
// CI machines where simulator animations / keyboard transitions take longer
// than on a developer's desktop.
private enum UITestTimeout {
    /// Standard wait for UI state to settle (keyboard appear/dismiss,
    /// text field value change, animation completion). 10s is generous
    /// enough for a loaded CI runner while still catching true hangs.
    static let uiSettle: TimeInterval = 10.0

    /// Longer budget for operations that include app/host seeding or
    /// SwiftData writes that must propagate before UI is ready.
    static let appSeed: TimeInterval = 15.0
}

final class ExercisePickerSearchFocusUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: T1 — single-select debounce

    /// T1: Typing "bench" letter-by-letter across the 200ms debounce window
    /// must not lose search focus or dismiss the keyboard between chars.
    @MainActor
    func test_searchFocus_persistsAcrossDebouncedContentChange() throws {
        let app = launchPicker(mode: "single")

        let searchField = openSearchField(in: app)
        typeAndAssertKeyboardStaysUp(app: app, searchField: searchField, text: "bench")
    }

    // MARK: T2 — multi-select debounce

    @MainActor
    func test_searchFocus_persistsInMultiSelect() throws {
        let app = launchPicker(mode: "multi")

        let searchField = openSearchField(in: app)
        typeAndAssertKeyboardStaysUp(app: app, searchField: searchField, text: "bench")
    }

    // MARK: T3 — scrollResetToken bump

    /// T3: The `.onChange(debouncedSearchText)` handler bumps
    /// `scrollResetToken` and calls `gridProxy.scrollTo(...)` after the
    /// 200ms debounce. That programmatic scroll must not dismiss the
    /// keyboard even though `.scrollDismissesKeyboard(.immediately)` is
    /// active — the reset targets a section anchor, not user drag.
    @MainActor
    func test_searchFocus_persistsAfterScrollResetTokenBump() throws {
        let app = launchPicker(mode: "single")

        let searchField = openSearchField(in: app)
        searchField.typeText("b")
        // Wait past the 200ms debounce so `debouncedSearchText` updates and
        // `scrollResetToken` bumps, triggering the programmatic
        // `gridProxy.scrollTo(...)`.
        usleep(400_000)
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Keyboard dismissed after scrollResetToken bump")
        XCTAssertTrue(searchField.hasKeyboardFocus,
                      "Search field lost focus after scrollResetToken bump")
    }

    // MARK: T4 — @Query refresh

    /// T4: Inserting a new Exercise into SwiftData while the user is typing
    /// causes `@Query` to re-emit, which drives
    /// `.onChange(of: exercises)` and rebuilds the grid. The search field
    /// must retain focus across this refresh — this is the core bug of
    /// MY-1368. The test uses `-ExercisePickerTestSeedTrigger 1` to mount a
    /// hittable seed button that performs the SwiftData insert.
    @MainActor
    func test_searchFocus_persistsAcrossQueryRefresh() throws {
        let app = launchPicker(mode: "single",
                               extraArgs: ["-ExercisePickerTestSeedTrigger", "1"])

        let searchField = openSearchField(in: app)

        // Type one char + wait past debounce so @Query is stable then mutate.
        searchField.typeText("t")
        usleep(400_000)
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Keyboard dismissed after initial type (before mutation)")

        // Trigger SwiftData insert of `TestSeedExercise`. The seed button
        // is visually hidden but hittable.
        let seedTrigger = app.buttons["ExercisePickerTestSeedTrigger"]
        XCTAssertTrue(seedTrigger.waitForExistence(timeout: UITestTimeout.appSeed),
                      "Seed trigger button not found")
        seedTrigger.tap()

        // Give SwiftData insert + @Query re-emit + `.onChange(exercises)`
        // rebuild time to complete. The seeded row may be off-screen in
        // the lazy grid (barbell section can be scrolled away), so we
        // don't require it to be hittable — instead we assert on the
        // OBSERVABLE outcome: after the mutation propagates, the search
        // field must still hold focus and the keyboard must still be up.
        // This is the exact contract MY-1368 violated.
        usleep(1_000_000) // 1s — beyond @Query re-emit + rebuild

        // Now assert focus survived the refresh.
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Keyboard dismissed after @Query refresh — CORE BUG")
        XCTAssertTrue(searchField.hasKeyboardFocus,
                      "Search field lost focus after @Query refresh — CORE BUG")
    }

    // MARK: T6 — zero-result transitions (MY-1418 / MY-1419)

    /// T6a: Filtering the picker down to ZERO results must not dismiss the
    /// keyboard or drop search focus. `exerciseCardGrid` used to be an
    /// `if equipmentGroups.isEmpty { emptyState } else { ScrollView { … } }`
    /// pair of mutually exclusive subtrees, so a query that matched nothing
    /// tore the `ScrollView` — and with it the
    /// `.scrollDismissesKeyboard(.immediately)` modifier — out of the
    /// hierarchy. UIKit resigned first responder as part of that teardown
    /// even though the user never made a drag gesture. The user must be able
    /// to keep editing (e.g. backspace a typo) without re-tapping the field.
    @MainActor
    func test_searchFocus_persistsWhenSearchYieldsNoResults() throws {
        let app = launchPicker(mode: "single")

        let searchField = openSearchField(in: app)
        // `zzzzz` matches no seeded exercise in either nameEn or nameZh, so
        // `computeEquipmentGroups` returns [] and the grid flips to its
        // empty state.
        typeAndAssertKeyboardStaysUp(app: app, searchField: searchField, text: "zzzzz")
    }

    /// T6b: Same contract on the multi-select entry point.
    @MainActor
    func test_searchFocus_persistsWhenSearchYieldsNoResultsInMultiSelect() throws {
        let app = launchPicker(mode: "multi")

        let searchField = openSearchField(in: app)
        typeAndAssertKeyboardStaysUp(app: app, searchField: searchField, text: "zzzzz")
    }

    /// T6c: Editing back OUT of the zero-result state must keep focus too —
    /// the round trip non-empty → empty → non-empty crosses the grid's
    /// content/empty boundary twice, and focus must survive both crossings
    /// so the user never has to re-tap the field mid-correction.
    @MainActor
    func test_searchFocus_persistsWhenEditingBackFromNoResults() throws {
        let app = launchPicker(mode: "single")

        let searchField = openSearchField(in: app)
        // "bench" matches; appending "zzz" drops the result set to zero.
        typeAndAssertKeyboardStaysUp(app: app, searchField: searchField, text: "benchzzz")

        // Backspace out of the zero-result state one char at a time. Focus
        // and keyboard must hold across the empty → populated crossing.
        for index in 0..<3 {
            searchField.typeText(XCUIKeyboardKey.delete.rawValue)
            usleep(300_000) // > 200ms debounce
            XCTAssertTrue(app.keyboards.firstMatch.exists,
                          "Keyboard dismissed while deleting char index \(index)")
            XCTAssertTrue(searchField.hasKeyboardFocus,
                          "Search field lost focus while deleting char index \(index)")
        }
    }

    /// T6d: The empty state must stay scrollable so a user drag over it
    /// still dismisses the keyboard — the fix keeps the `ScrollView`
    /// mounted, so `.scrollDismissesKeyboard(.immediately)` must remain
    /// live in the zero-result state exactly as it is with results (T5c).
    @MainActor
    func test_scrollDismissesKeyboard_onEmptyState() throws {
        let app = launchPicker(mode: "single",
                               extraArgs: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryM"])
        let searchField = openSearchField(in: app)
        searchField.typeText("zzzzz")
        usleep(400_000) // > 200ms debounce → grid is now in the empty state
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Keyboard missing before swipe on empty state")

        // Same coordinate-based drag as T5c — top ~40% of the window, well
        // clear of both the keyboard and the floating panel.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        start.press(forDuration: 0.05, thenDragTo: end)

        let noKeyboard = expectation(for: NSPredicate(format: "exists == false"),
                                    evaluatedWith: app.keyboards.firstMatch,
                                    handler: nil)
        wait(for: [noKeyboard], timeout: UITestTimeout.uiSettle)
    }

    // MARK: T5 — explicit dismiss paths (regression guard)

    /// T5a: Tapping the navigation-bar cancel button dismisses the sheet.
    @MainActor
    func test_searchFocus_cancelButtonDismissesSheet() throws {
        let app = launchPicker(mode: "single")
        let searchField = openSearchField(in: app)
        searchField.typeText("b")
        usleep(300_000)

        // Cancel button — matches by label ("取消" / "Cancel") via a11y.
        // firstMatch on nav-bar buttons is fragile across iOS versions
        // (iOS 18 may include an implicit back/drag chevron ahead of the
        // real cancel button), so match by label directly.
        let cancelButton = app.navigationBars.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "取消", "Cancel")
        ).firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 1.0),
                      "Cancel button not found in nav bar")
        cancelButton.tap()

        // Sheet dismissed → search field gone from hierarchy.
        XCTAssertFalse(searchField.waitForExistence(timeout: 0.5),
                       "Cancel did not dismiss the picker sheet")
    }

    /// T5b: Non-empty search + tap clear button → keyboard collapses,
    /// search text cleared, `isSearchExpanded` resets.
    @MainActor
    func test_searchFocus_clearButtonResetsSearch() throws {
        let app = launchPicker(mode: "single")
        let searchField = openSearchField(in: app)
        searchField.typeText("b")
        usleep(300_000)
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Keyboard missing before clear")

        // Clear button — matches by a11y label ("清除搜索" / "Clear search")
        // or by systemImage "xmark.circle.fill" fallback. Search across
        // all buttons in the picker sheet.
        let clearButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "清除", "Clear", "xmark")
        ).firstMatch
        XCTAssertTrue(clearButton.waitForExistence(timeout: 1.0),
                      "Clear button not found — labels visible: \(app.buttons.allElementsBoundByIndex.map { $0.label })")
        clearButton.tap()

        // After clear: search text should reset. Focus behaviour differs
        // by platform; the spec only mandates that the search text and
        // expansion state reset — keyboard dismissal is a consequence of
        // isSearchFocused = false which happens in the same closure.
        // Assert that the field is empty or hidden after collapse (the
        // observable contract) rather than keyboard visibility (which iOS
        // may keep for a beat during the collapse animation).
        let resetPredicate = NSPredicate(
            format: "exists == false OR value == %@ OR value == nil OR value == %@",
            "",
            "Search exercises"
        )
        let emptyField = expectation(for: resetPredicate,
                                    evaluatedWith: searchField,
                                    handler: nil)
        wait(for: [emptyField], timeout: UITestTimeout.uiSettle)
    }

    /// T5c: Non-empty search + user swipe on the grid dismisses keyboard
    /// via `.scrollDismissesKeyboard(.immediately)`.
    @MainActor
    func test_searchFocus_scrollDismissesKeyboard() throws {
        let app = launchPicker(mode: "single",
                               extraArgs: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryM"])
        let searchField = openSearchField(in: app)
        searchField.typeText("b")
        usleep(300_000)
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Keyboard missing before swipe")

        // Coordinate-based swipe on the top ~40% of the window (well above
        // both the keyboard and the floating panel). This reliably hits
        // the vertical exercise-card grid regardless of accessibility-tree
        // matching. `scrollDismissesKeyboard(.immediately)` fires as soon
        // as any drag gesture starts on the grid ScrollView.
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        start.press(forDuration: 0.05, thenDragTo: end)

        let noKeyboard = expectation(for: NSPredicate(format: "exists == false"),
                                    evaluatedWith: app.keyboards.firstMatch,
                                    handler: nil)
        wait(for: [noKeyboard], timeout: UITestTimeout.uiSettle)
    }

    /// T5d: Keyboard return key dismisses focus via platform default (single
    /// -line TextField + `.submitLabel(.search)`, no `.onSubmit` override).
    @MainActor
    func test_searchFocus_returnKeyDismissesFocus() throws {
        let app = launchPicker(mode: "single")
        let searchField = openSearchField(in: app)
        searchField.typeText("b")
        usleep(300_000)
        XCTAssertTrue(app.keyboards.firstMatch.exists,
                      "Keyboard missing before return")

        // Try the platform search key first; fall back to typing newline.
        let searchKey = app.keyboards.buttons["Search"]
        if searchKey.exists {
            searchKey.tap()
        } else if app.keyboards.buttons["搜索"].exists {
            app.keyboards.buttons["搜索"].tap()
        } else {
            searchField.typeText("\n")
        }

        let noKeyboard = expectation(for: NSPredicate(format: "exists == false"),
                                    evaluatedWith: app.keyboards.firstMatch,
                                    handler: nil)
        wait(for: [noKeyboard], timeout: UITestTimeout.uiSettle)
    }

    // MARK: helpers

    @MainActor
    private func launchPicker(mode: String, extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ExercisePickerTestMode", mode] + extraArgs
        // Disable animations to reduce flake around focus transitions.
        app.launchArguments += ["-UIAnimationsEnabled", "NO"]
        app.launch()
        return app
    }

    /// Locates the search text field within the presented picker sheet.
    /// The picker mounts a collapsed magnifier button first; tapping it
    /// expands to the full `searchRow` with the TextField. In case the
    /// picker already renders expanded (some configurations), the tap is
    /// a no-op we then re-query.
    @MainActor
    private func openSearchField(in app: XCUIApplication) -> XCUIElement {
        // Wait for the picker sheet to appear (navigation title present).
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5.0)

        // Try the expanded field directly first.
        var field = app.textFields.firstMatch
        if !field.waitForExistence(timeout: 1.0) {
            // Not expanded — tap the collapsed magnifier button by a11y
            // label ("搜索动作" / "Search exercises").
            let magnifier = app.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                            "搜索", "Search")
            ).firstMatch
            if magnifier.exists {
                magnifier.tap()
            }
            field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: UITestTimeout.uiSettle),
                          "Search text field never appeared")
        }

        // Ensure focus by tapping.
        if !field.hasKeyboardFocus {
            field.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: UITestTimeout.uiSettle),
                      "Keyboard did not appear after focusing search field")
        return field
    }

    /// Type text char-by-char, waiting past the 200ms debounce after each
    /// keystroke, and assert the keyboard + focus survive each debounce
    /// tick.
    @MainActor
    private func typeAndAssertKeyboardStaysUp(app: XCUIApplication,
                                              searchField: XCUIElement,
                                              text: String) {
        for (index, char) in text.enumerated() {
            searchField.typeText(String(char))
            // sleep(0.3) > 200ms debounce → forces the
            // `.onChange(debouncedSearchText)` chain to run.
            usleep(300_000)
            XCTAssertTrue(app.keyboards.firstMatch.exists,
                          "Keyboard dismissed after char index \(index) ('\(char)')")
            XCTAssertTrue(searchField.hasKeyboardFocus,
                          "Search field lost focus after char index \(index) ('\(char)')")
        }
    }
}

private extension XCUIElement {
    /// Convenience wrapper matching Apple's WWDC UI-test pattern for
    /// checking `@FocusState`-driven focus on a TextField.
    var hasKeyboardFocus: Bool {
        (value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }
}
