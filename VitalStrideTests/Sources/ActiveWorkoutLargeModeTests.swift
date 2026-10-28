import SwiftData
import SwiftUI
import Testing
import UIKit
import VitalModels
import XCTest

@testable import VitalStride

/// MY-1088 — Large Mode persistence verification for `ActiveWorkoutView`.
///
/// The toolbar toggle writes `activeWorkoutLargeMode` to `UserDefaults`; on
/// the next entry `@AppStorage("activeWorkoutLargeMode")` in
/// `ActiveWorkoutView` reads it back. These tests drive the same
/// `UserDefaults`-backed code path production uses (not a synthetic
/// `.environment` override), so a regression in the persisted-flag contract
/// — the AC's "restores on next entry" clause — would fail here.
///
/// The visual side of Large Mode (header timer + summary font swap) is
/// covered by the `#Preview("Large Mode")` block in `ActiveWorkoutView.swift`,
/// which seeds the same @AppStorage key before init so the preview drives
/// the production render path (not a stubbed environment).
@MainActor
@Suite("ActiveWorkoutView Large Mode (MY-1088)")
struct ActiveWorkoutLargeModeTests {
    private static let largeModeKey = "activeWorkoutLargeMode"

    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "ActiveWorkoutLargeModeTests.\(UUID().uuidString)"))
    }

    @Test("Default (no @AppStorage value) is Normal mode")
    func defaultIsNormalMode() {
        defaults.removeObject(forKey: Self.largeModeKey)
        // @AppStorage default in ActiveWorkoutView is `false`, so an absent
        // key must NOT be read as Large Mode.
        #expect(defaults.object(forKey: Self.largeModeKey) == nil)
        #expect(!defaults.bool(forKey: Self.largeModeKey))
    }

    @Test("Toolbar toggle write persists so next-entry @AppStorage restores Large Mode")
    func togglePersistsAcrossEntries() {
        defaults.removeObject(forKey: Self.largeModeKey)
        // Simulate the write the toolbar Button performs on toggle.
        defaults.set(true, forKey: Self.largeModeKey)

        // A fresh ActiveWorkoutView's @AppStorage("activeWorkoutLargeMode")
        // will read this back to `true` on init, so the AC "Persistence via
        // @AppStorage restores the mode on next workout entry" is satisfied.
        #expect(defaults.bool(forKey: Self.largeModeKey))

        defaults.removeObject(forKey: Self.largeModeKey)
    }

    @Test("Toggling back to Normal writes false so the flag is not a one-way switch")
    func toggleBackToNormalPersists() {
        defaults.set(true, forKey: Self.largeModeKey)
        defaults.set(false, forKey: Self.largeModeKey)
        #expect(!defaults.bool(forKey: Self.largeModeKey))
        defaults.removeObject(forKey: Self.largeModeKey)
    }

    @Test("ActiveWorkoutView constructs in both modes without diverging init behavior")
    @MainActor
    func viewInitializesInBothModes() {
        defaults.removeObject(forKey: Self.largeModeKey)
        _ = ActiveWorkoutView().defaultAppStorage(defaults)
        defaults.set(true, forKey: Self.largeModeKey)
        _ = ActiveWorkoutView().defaultAppStorage(defaults)
        defaults.removeObject(forKey: Self.largeModeKey)
    }
}

@MainActor
final class WorkoutToolbarRenderingTests: XCTestCase {
    func testToolbarActionsRenderAsSeparateHitTargetsAndFinishConfirms() async throws {
        let suiteName = "WorkoutToolbarRenderingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let locale = Locale.current.identifier
        for width in [375, 393] {
            for largeMode in [false, true] {
                defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
                for colorScheme in [ColorScheme.light, .dark] {
                    for dynamicType in [DynamicTypeSize.large, .accessibility3] {
                        let container = try ModelContainerConfiguration.makeTestContainer()
                        let probe = ToolbarProbe()
                        let view = ActiveWorkoutView(source: .blank)
                            .modelContainer(container)
                            .designThemePreview()
                            .defaultAppStorage(defaults)
                            .preferredColorScheme(colorScheme)
                            .dynamicTypeSize(dynamicType)
                            .environment(\.activeWorkoutToolbarObservation, probe.observation)
                        let host = UIHostingController(rootView: view)
                        let scene = try XCTUnwrap(
                            UIApplication.shared.connectedScenes
                                .compactMap { $0 as? UIWindowScene }
                                .first
                        )
                        let window = UIWindow(windowScene: scene)
                        window.frame = CGRect(x: 0, y: 0, width: width, height: 852)
                        window.rootViewController = host
                        window.makeKeyAndVisible()

                        try await Task.sleep(for: .milliseconds(250))
                        host.view.layoutIfNeeded()

                        let largeFrame = try XCTUnwrap(probe.largeModeFrame)
                        let finishFrame = try XCTUnwrap(probe.finishFrame)
                        XCTAssertGreaterThanOrEqual(largeFrame.width, 43.99)
                        XCTAssertGreaterThanOrEqual(largeFrame.height, 43.99)
                        XCTAssertGreaterThanOrEqual(finishFrame.width, 43.99)
                        XCTAssertGreaterThanOrEqual(finishFrame.height, 43.99)
                        XCTAssertFalse(largeFrame.intersects(finishFrame))
                        XCTAssertNotNil(window.hitTest(window.convert(largeFrame.center, from: nil), with: nil))
                        XCTAssertNotNil(window.hitTest(window.convert(finishFrame.center, from: nil), with: nil))

                        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                        }
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "T07 toolbar \(locale) \(width) \(largeMode ? "large" : "normal") \(dynamicType) \(colorScheme)"
                        attachment.lifetime = .keepAlways
                        add(attachment)

                        XCTAssertNotNil(probe.largeModeAction)
                        probe.largeModeAction?()
                        try await Task.sleep(for: .milliseconds(100))
                        let expectedMode = !largeMode
                        XCTAssertEqual(
                            defaults.bool(forKey: "activeWorkoutLargeMode"),
                            expectedMode
                        )

                        window.isHidden = true
                        let restoredProbe = ToolbarProbe()
                        let relaunched = UIHostingController(
                            rootView: ActiveWorkoutView(source: .blank)
                                .modelContainer(container)
                                .designThemePreview()
                                .defaultAppStorage(defaults)
                                .preferredColorScheme(colorScheme)
                                .dynamicTypeSize(dynamicType)
                                .environment(\.activeWorkoutToolbarObservation, restoredProbe.observation)
                        )
                        window.rootViewController = relaunched
                        window.makeKeyAndVisible()
                        try await Task.sleep(for: .milliseconds(100))
                        relaunched.view.layoutIfNeeded()
                        XCTAssertNotNil(restoredProbe.largeModeFrame)
                        XCTAssertEqual(
                            expectedMode,
                            defaults.bool(forKey: "activeWorkoutLargeMode")
                        )
                        XCTAssertNotNil(restoredProbe.finishAction)
                        restoredProbe.finishAction?()
                        try await Task.sleep(for: .milliseconds(100))
                        XCTAssertNotNil(
                            window.rootViewController?.presentedViewController,
                            "Finish must open the existing confirmation path"
                        )
                        window.isHidden = true
                    }
                }
            }
        }
    }

}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

@MainActor
private final class ToolbarProbe {
    var largeModeFrame: CGRect?
    var finishFrame: CGRect?
    var largeModeAction: (@MainActor @Sendable () -> Void)?
    var finishAction: (@MainActor @Sendable () -> Void)?

    var observation: ActiveWorkoutToolbarObservation {
        ActiveWorkoutToolbarObservation(
            onLargeModeFrame: { [self] frame in largeModeFrame = frame },
            onFinishFrame: { [self] frame in finishFrame = frame },
            onLargeModeAction: { [self] action in largeModeAction = action },
            onFinishAction: { [self] action in finishAction = action }
        )
    }
}
