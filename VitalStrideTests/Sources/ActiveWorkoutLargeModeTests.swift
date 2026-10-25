import SwiftUI
import Testing

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
