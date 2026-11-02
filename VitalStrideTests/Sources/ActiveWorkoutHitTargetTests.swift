import SwiftUI
import Testing
import SwiftData
import VitalModels
import DesignKit

#if canImport(UIKit) && !os(macOS)
import UIKit
#endif

@testable import VitalStride

/// MY-1013 — Compact-row hit-target token verification for `SetRow` and
/// `SubSetRow`.
///
/// The MY-877 compact-row implementation used
/// `.frame(width: 44, height: 44).contentShape(...).padding(.vertical, -N)`
/// on the completion buttons and the ellipsis Menu trigger. The rendered
/// button was 44pt, but the negative vertical layout padding pulled the
/// row's layout claim below 44pt so the rendered button overhung the
/// neighboring row. Under the compact List row layout used by
/// `ActiveWorkoutView` (plain style, `defaultMinListRowHeight: 28`), two
/// adjacent rows' controls competed for the overlap and hit-test / VoiceOver
/// focus geometry were ambiguous — Constitution P1-H says the tappable and
/// accessibility target must be unambiguously >= 44pt.
///
/// MY-1013 removes the negative padding and pins the 44pt frame through a
/// single `ActiveWorkoutHitTarget.side` token. These tests pin the numeric
/// contract on that token (any regression that shrinks it below 44 fails
/// loudly), and the visual density that MY-877 delivered is preserved by
/// the pre-existing List insets in `ActiveExerciseSection` (2pt top/bottom
/// row insets, 16pt leading/trailing) and `defaultMinListRowHeight` (28pt)
/// in `ActiveWorkoutView` — none of which changed.
@Suite("Active Workout compact row hit target (MY-1013)")
struct ActiveWorkoutHitTargetTests {
    #if canImport(UIKit) && !os(macOS)
    @MainActor
    @Test("Mounted add-exercise pill has full-width geometry and edge/center activation")
    func mountedAddExerciseProbeContract() async throws {
        for largeMode in [false, true] {
            let result = try await MountedAddExerciseInteraction.check(largeMode: largeMode)
            #expect(result.visible.width >= 320)
            #expect(abs(result.hit.width - result.visible.width) <= 1)
            #expect(abs(result.hit.height - result.visible.height) <= 1)
            #expect(abs(result.hit.minX - result.visible.minX) <= 1)
            #expect(abs(result.hit.minY - result.visible.minY) <= 1)
            #expect(result.activations == 3)
        }
    }
    #endif

    @Test("SetRow/SubSetRow hit-target side is exactly 44pt (Constitution P1-H)")
    func hitTargetSideIsHigMinimum() {
        // 44pt is the Apple HIG floor and the Constitution P1-H requirement.
        // Both files funnel through this token so a single edit here would
        // regress every compact-row control at once — catch it in tests
        // rather than at review time.
        #expect(ActiveWorkoutHitTarget.side == 44)
    }

    @Test("SetRow/SubSetRow hit-target side meets Constitution P1-H (>=44pt)")
    func hitTargetSideMeetsConstitutionFloor() {
        // The exact-value test above pins the current token. This inequality
        // test pins the intent: even if a future refactor raises the token
        // (say, to 48pt) the constitutional floor must still hold.
        #expect(ActiveWorkoutHitTarget.side >= 44)
    }

    @Test("Numeric input keeps a compact visual pill inside its hit target")
    func numericInputPillUsesIndependentHitTargetContainer() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/ActiveWorkout/SetRow.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains(".frame(height: largeMode ? 42 : 36)"))
        #expect(source.contains(".frame(minWidth: ActiveWorkoutHitTarget.side, minHeight: ActiveWorkoutHitTarget.side)"))
        #expect(source.contains(".contentShape(Rectangle())"))
        #expect(source.contains("numericInputWidth("))
    }

    @Test("SetRow forwards outer pill taps to the inner UIKit input")
    func setRowPillTapFocusContract() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/ActiveWorkout/SetRow.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        #expect(source.contains("var focusRequestID: Int = 0"))
        #expect(source.contains("var lastFocusRequestID = 0"))
        #expect(source.contains("view.becomeFirstResponder()"))
        #expect(source.contains("focusRequestID.wrappedValue &+= 1"))
        #expect(source.contains("@State private var weightRightFocusRequestID = 0"))
        #expect(source.contains("$weightFocusRequestID"))
        #expect(source.contains("field: .weightRight, width: weightWidth, side: \"R\", suggestion: advice, compact: compact, focusRequestID: $weightRightFocusRequestID"))
        #expect(source.contains("$repsFocusRequestID"))
        #expect(source.contains("focusRequestID: focusRequestID.wrappedValue"))
    }

    @Test("Unilateral weight pills use independent focus request channels")
    func unilateralWeightPillFocusRequestsAreIndependent() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("VitalStride/Sources/ActiveWorkout/SetRow.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let leftBinding = "field: .weight, width: weightWidth"
        let rightBinding = "field: .weightRight, width: weightWidth"
        let leftRange = try #require(source.range(of: leftBinding))
        let rightRange = try #require(source.range(of: rightBinding))
        #expect(source[leftRange.lowerBound..<rightRange.lowerBound].contains("$weightFocusRequestID"))
        #expect(source[rightRange.lowerBound...].contains("$weightRightFocusRequestID"))
        #expect(!source[rightRange.lowerBound...].prefix(250).contains("$weightFocusRequestID"))
    }
}

#if canImport(UIKit) && !os(macOS)
/// Shared mounted interaction harness; failures throw in both XCTest and Swift Testing.
@MainActor
enum MountedAddExerciseInteraction {
    struct Result {
        let visible: CGRect
        let hit: CGRect
        let activations: Int
    }

    static func check(
        largeMode: Bool, isDark: Bool = false, slot: BottomSnackbarSlot = .none
    ) async throws -> Result {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let workout = Workout(type: .strength, startDate: Date(), exercises: [])
        container.mainContext.insert(workout)
        try container.mainContext.save()
        let suite = "TK1.MountedAdd.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { throw failure("Missing host scene/defaults") }
        defaults.set(largeMode, forKey: "activeWorkoutLargeMode")
        defer { defaults.removePersistentDomain(forName: suite) }
        var visibleFrame: CGRect?
        var hitFrame: CGRect?
        var tapCount = 0
        let content = ActiveWorkoutView(source: .resume(workout), snackbarSlotOverride: slot)
            .modelContainer(container)
            .environment(\.theme, Theme(seed: .teal, neutral: .slate, isDark: isDark))
            .environment(\.activeWorkoutListObservation, ActiveWorkoutListObservationSink(
                onAddExerciseVisibleFrame: { visibleFrame = $0 },
                onAddExerciseHitFrame: { hitFrame = $0 },
                onAddExerciseAction: { tapCount += 1 }
            ))
            .defaultAppStorage(defaults)
        let host = UIHostingController(rootView: content)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        guard let visible = visibleFrame, let hit = hitFrame,
              visible.width >= 320,
              abs(hit.width - visible.width) <= 1,
              abs(hit.height - visible.height) <= 1,
              abs(hit.minX - visible.minX) <= 1,
              abs(hit.minY - visible.minY) <= 1
        else { throw failure("Visible/hit frame parity: \(String(describing: visibleFrame)) / \(String(describing: hitFrame))") }

        let points = [CGPoint(x: visible.minX + 8, y: visible.midY),
                      CGPoint(x: visible.midX, y: visible.midY),
                      CGPoint(x: visible.maxX - 8, y: visible.midY)]
        var mountedControl: UIControl?
        for (index, point) in points.enumerated() {
            guard let target = host.view.hitTest(point, with: nil) as? UIControl,
                  target.accessibilityIdentifier == "workout_add_exercise_hit_surface",
                  mountedControl == nil || mountedControl === target
            else { throw failure("Point \(point) missed the mounted add-exercise control") }
            mountedControl = target
            let nativeFrame = target.convert(target.bounds, to: host.view)
            guard abs(nativeFrame.width - visible.width) <= 1,
                  abs(nativeFrame.height - visible.height) <= 1,
                  abs(nativeFrame.minX - visible.minX) <= 1,
                  abs(nativeFrame.minY - visible.minY) <= 1
            else { throw failure("Native interactive bounds differ from the visible pill") }
            // Dispatch the same UIControl event produced by a successful touch;
            // the primitive style triggers the original SwiftUI Button action.
            target.sendActions(for: .touchUpInside)
            guard tapCount == index + 1 else { throw failure("Mounted activation count=\(tapCount), expected=\(index + 1)") }
        }
        try await Task.sleep(for: .milliseconds(500))
        host.presentedViewController?.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(200))
        return Result(visible: visible, hit: hit, activations: tapCount)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TK1.MountedAddExercise", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
#endif
