import AIService
import SwiftUI

/// SwiftUI environment plumbing for the app-target `RoutingSignalStore`
/// (spec 019 Stage 3c). All 11 AI-caller views resolve `\.routingSignalStore`
/// out of the environment and hand it to `AIRouterFactory.makeDefault(…)`.
/// The store lives for the lifetime of the app and is installed in
/// `VitalStrideApp` / `VitalStrideMacApp` right beside the `ModelContainer`.
///
/// Design note: kept as `(any RoutingSignalSink)?` at the environment
/// boundary so previews (which do NOT install a real store) skip the write
/// path entirely — the router installs its own `NoOpRoutingSignalSink` and
/// no `RoutingSignalEntry` rows land, keeping previews and unit tests off
/// the SwiftData store on the `.none` partition.
private struct RoutingSignalStoreKey: EnvironmentKey {
    static let defaultValue: RoutingSignalStore? = nil
}

extension EnvironmentValues {
    var routingSignalStore: RoutingSignalStore? {
        get { self[RoutingSignalStoreKey.self] }
        set { self[RoutingSignalStoreKey.self] = newValue }
    }
}
