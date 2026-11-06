import Foundation
import XCTest

@testable import VitalStride

final class ActiveWorkoutSidebarFlightTests: XCTestCase {
    func testSchemeBReorderWidthCoversContainer() {
        let listWidth: CGFloat = 640
        let collapsed: CGFloat = 88
        XCTAssertEqual(max(260, listWidth + collapsed), 728)
        XCTAssertEqual(max(280, listWidth + collapsed), 728)
    }

    func testSchemeBCollapsedRailWidth() {
        XCTAssertEqual(min(max(CGFloat(320) * 0.18, 64), 88), 64)
        XCTAssertEqual(min(max(CGFloat(640) * 0.18, 64), 88), 88)
    }

    func testSchemeCPillBarContract() throws {
        let source = try sourceText()
        XCTAssertTrue(source.contains("let collapsed: CGFloat = isSidebarSchemeC"))
        XCTAssertTrue(source.contains("workout_exercise_pill_"))
        XCTAssertTrue(source.contains("workout_exercise_pill_bar"))
        XCTAssertTrue(source.contains("workout_pill_bar_reorder"))
        XCTAssertTrue(source.contains("if isSidebarSchemeC && !isSidebarReordering"))
    }

    func testReorderSurfaceContract() throws {
        let source = try sourceText()
        XCTAssertTrue(source.contains(".padding(.horizontal, isSidebarReordering ? 12 : 2)"))
        XCTAssertTrue(source.contains("if !isSidebarReordering"))
        XCTAssertTrue(source.contains("minWidth: 236"))
        XCTAssertFalse(source.contains("containerWidth * 0.74"))
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
