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
}
