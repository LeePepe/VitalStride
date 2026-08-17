import Foundation
import Testing

/// MY-1426 — the set-deletion undo snackbar's two strings used the Chinese
/// literals `撤销` / `撤销删除` as catalog keys while every other string in the
/// feature lives under `active_workout.set_delete.*`. Renaming a key is silent
/// at compile time: `String(localized:defaultValue:)` falls back to the
/// `defaultValue` when the catalog entry is missing, so a half-applied rename
/// still shows "Undo" in English and only breaks zh-Hans.
///
/// These assertions read the compiled catalog directly (bundled into the host
/// app via `Localizable.xcstrings`) so a missing entry fails the test instead
/// of hiding behind the in-code default.
@Suite("Set-deletion undo localization keys (MY-1426)")
struct SetDeletionUndoLocalizationTests {
    /// Sentinel returned by `localizedString(forKey:value:table:)` when the key
    /// is absent, chosen so it can never collide with a real translation.
    private static let missing = "__key_absent__"

    private func catalogValue(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: Self.missing, table: nil)
    }

    @Test("Namespaced undo keys resolve from the catalog")
    func namespacedKeysExist() {
        for key in [
            "active_workout.set_delete.undo_action",
            "active_workout.set_delete.undo_action_a11y",
        ] {
            let value = catalogValue(key)
            #expect(value != Self.missing, "Missing catalog entry for \(key)")
            #expect(value != key, "\(key) resolved to the key itself")
        }
    }

    @Test("Legacy Chinese-literal undo keys are gone")
    func legacyLiteralKeysRemoved() {
        for key in ["撤销", "撤销删除"] {
            #expect(
                catalogValue(key) == Self.missing,
                "Legacy literal key \(key) is still in the catalog"
            )
        }
    }
}
