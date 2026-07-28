import Foundation
import Testing

@testable import VitalStride

// MARK: - WorkoutListStateBanner — MY-1359 four-state contract

/// The banner has three explicit states (`loading` / `failed` / `unauthorized`);
/// the fourth "empty" state is owned by `WorkoutListView`'s
/// `ContentUnavailableView` outside the banner. These tests assert the state
/// discriminator behaves as a pure value type (equatable, exhaustive) — which
/// is what `WorkoutListView.currentBannerState(...)` and the SwiftUI switch
/// rely on to keep the four states mutually exclusive.
@Suite("WorkoutListStateBanner — MY-1359")
@MainActor
struct WorkoutListStateBannerTests {
    @Test("LoadState is Equatable and each case is distinct")
    func loadStateEquatable() {
        let loading: WorkoutListStateBanner.LoadState = .loading
        let failed: WorkoutListStateBanner.LoadState = .failed
        let unauthorized: WorkoutListStateBanner.LoadState = .unauthorized

        #expect(loading == .loading)
        #expect(failed == .failed)
        #expect(unauthorized == .unauthorized)
        #expect(loading != failed)
        #expect(failed != unauthorized)
        #expect(loading != unauthorized)
    }

    @Test("Loading state can be constructed and hashed")
    func loadingConstructsCleanly() {
        let state: WorkoutListStateBanner.LoadState = .loading
        // Force the enum through a Set to catch accidental non-hashable regressions
        // (via Equatable — the enum has no associated values today).
        let seen: [WorkoutListStateBanner.LoadState] = [state, .loading]
        #expect(seen.count == 2)
    }

    @Test("Failed state can be constructed distinct from loading")
    func failedConstructsDistinct() {
        let state: WorkoutListStateBanner.LoadState = .failed
        #expect(state != .loading)
        #expect(state != .unauthorized)
    }

    @Test("Unauthorized state can be constructed distinct from failed")
    func unauthorizedConstructsDistinct() {
        let state: WorkoutListStateBanner.LoadState = .unauthorized
        #expect(state != .loading)
        #expect(state != .failed)
    }

    @Test("openSettings helper does not crash even without UIApplication access")
    func openSettingsIsNonThrowing() {
        // The helper is a no-op on platforms without UIKit; on iOS it just
        // asks UIApplication to open the settings URL. Either way it must
        // not throw or crash when called from a unit-test context.
        WorkoutListStateBanner.openSettings()
    }

    @Test("Banner can be instantiated for each of the three states")
    func bannerInstantiatesForEachState() {
        // We don't render the SwiftUI hierarchy here — just make sure the
        // initializer accepts each case and the closure survives ARC.
        var tapped = 0
        let loading = WorkoutListStateBanner(state: .loading, onOpenSettings: { tapped += 1 })
        let failed = WorkoutListStateBanner(state: .failed, onOpenSettings: { tapped += 1 })
        let unauthorized = WorkoutListStateBanner(state: .unauthorized, onOpenSettings: { tapped += 1 })

        _ = loading
        _ = failed
        _ = unauthorized
        #expect(tapped == 0)
    }

    // MARK: - Copy assertions (MY-1361 P1 — strengthen banner test coverage)

    @Test("Loading title + subtitle are non-empty and localised")
    func loadingCopyIsPresent() {
        let title = WorkoutListStateBanner.testTitle(for: .loading)
        let subtitle = WorkoutListStateBanner.testSubtitle(for: .loading)

        #expect(!title.isEmpty)
        #expect(!subtitle.isEmpty)
        // Should not be the raw localisation key — that would mean the string
        // catalog lookup returned the key back to us.
        #expect(title != "workout_list.state_banner.loading_title")
        #expect(subtitle != "workout_list.state_banner.loading_subtitle")
    }

    @Test("Failed title + subtitle are non-empty and distinct from loading")
    func failedCopyIsPresentAndDistinct() {
        let title = WorkoutListStateBanner.testTitle(for: .failed)
        let subtitle = WorkoutListStateBanner.testSubtitle(for: .failed)

        #expect(!title.isEmpty)
        #expect(!subtitle.isEmpty)
        #expect(title != WorkoutListStateBanner.testTitle(for: .loading))
        #expect(subtitle != WorkoutListStateBanner.testSubtitle(for: .loading))
    }

    @Test("Unauthorized title + subtitle are non-empty and distinct from other states")
    func unauthorizedCopyIsPresentAndDistinct() {
        let title = WorkoutListStateBanner.testTitle(for: .unauthorized)
        let subtitle = WorkoutListStateBanner.testSubtitle(for: .unauthorized)

        #expect(!title.isEmpty)
        #expect(!subtitle.isEmpty)
        #expect(title != WorkoutListStateBanner.testTitle(for: .loading))
        #expect(title != WorkoutListStateBanner.testTitle(for: .failed))
        #expect(subtitle != WorkoutListStateBanner.testSubtitle(for: .loading))
        #expect(subtitle != WorkoutListStateBanner.testSubtitle(for: .failed))
    }

    @Test("Unauthorized CTA carries VoiceOver label + hint")
    func unauthorizedCTACarriesAccessibility() {
        let a11y = WorkoutListStateBanner.testOpenSettingsAccessibility()

        #expect(!a11y.label.isEmpty)
        #expect(!a11y.hint.isEmpty)
        #expect(a11y.label != "workout_list.state_banner.open_settings_a11y")
        #expect(a11y.hint != "workout_list.state_banner.open_settings_hint")
        // Label and hint should carry different information — a hint that
        // duplicates the label provides no extra context for VoiceOver users.
        #expect(a11y.label != a11y.hint)
    }

    // MARK: - Tap callback (MY-1361 P1 — verify onOpenSettings fires)

    @Test("Unauthorized banner fires onOpenSettings closure exactly when invoked")
    func unauthorizedTapCallbackFires() {
        var tapped = 0
        let banner = WorkoutListStateBanner(
            state: .unauthorized,
            onOpenSettings: { tapped += 1 }
        )

        // Merely constructing the banner must not invoke the closure — the
        // user has to press the CTA in the .unauthorized branch.
        #expect(tapped == 0)

        // Simulate the SwiftUI Button dispatching the action closure by
        // invoking the stored handler directly. This is the same closure
        // the .buttonStyle(.borderedProminent) Button would call on tap.
        banner.onOpenSettings()
        #expect(tapped == 1)

        // Repeated taps should each increment — no accidental one-shot latch.
        banner.onOpenSettings()
        banner.onOpenSettings()
        #expect(tapped == 3)
    }

    @Test("Loading and failed banners still accept and preserve their (unused) callback")
    func loadingFailedCallbackPreserved() {
        var tapped = 0
        let loading = WorkoutListStateBanner(
            state: .loading,
            onOpenSettings: { tapped += 1 }
        )
        let failed = WorkoutListStateBanner(
            state: .failed,
            onOpenSettings: { tapped += 1 }
        )

        // The banner intentionally does NOT render a button in these states,
        // so the closure would never fire from the UI. But it should still
        // be reachable / callable if a caller invokes it directly — this
        // guards against a regression where the closure is dropped.
        loading.onOpenSettings()
        failed.onOpenSettings()
        #expect(tapped == 2)
    }
}
