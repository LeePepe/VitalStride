import AIService
import Foundation
import HealthKitService
import OSLog
import SwiftData
import VitalModels

/// App-target sink for `RoutingSignal` values emitted by `AIRouter.execute`
/// (spec 019 Stage 3c, T017). Writes each signal as a `RoutingSignalEntry`
/// row into the local SwiftData `Telemetry` partition — the container that
/// `ModelContainerConfiguration.makeContainer` builds with
/// `cloudKitDatabase: .none`. That partition is the ONLY landing zone for
/// routing telemetry (FR-018 / 原则 I): rows never leave the device, never
/// go through unified log, Aptabase, GlitchTip, or CloudKit.
///
/// `record(_:)` is called by the router from a detached best-effort Task
/// wrapped in `try?`. So the store can throw or run slow without stalling
/// AI calls (FR-008). We still guard our own catch so an inserted error
/// path here surfaces a category-only os_log entry — never the raw signal
/// payload.
///
/// The store also exposes `updateLatestAccepted(kind:accepted:)` so the app
/// can retro-write `accepted` on the most recent signal of a given kind
/// after a user-driven acceptance/rejection happens (substitute apply →
/// accepted=true; chat regenerate → accepted=false on the just-completed
/// reply; workout finish etc.). Updating the latest row (rather than
/// inserting a new one) keeps signal count == request count and avoids
/// duplicate rows drifting the analysis downstream Stage 4/5 wants to run.
public final class RoutingSignalStore: RoutingSignalSink, AuthorizationRevocationHandling, @unchecked Sendable {

    private static let logger = Logger(
        subsystem: "com.vitalstride",
        category: "RoutingSignalStore"
    )

    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    public func record(_ signal: RoutingSignal) async throws {
        // `ModelContext` must be created on the actor it will be used on;
        // a fresh context per write keeps this off the main context and
        // isolated to this call. `container` itself is `Sendable`.
        let container = self.container
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let entry = RoutingSignalEntry(
                kind: signal.kind.rawValue,
                provider: signal.provider,
                deviceTier: signal.deviceTier.rawValue,
                latencyMs: signal.latencyMs,
                schemaValid: signal.schemaValid,
                accepted: signal.accepted,
                timestamp: signal.timestamp
            )
            context.insert(entry)
            do {
                try context.save()
            } catch {
                // FR-018 / 原则 I: log CATEGORY only. Never surface the
                // signal payload or the error's `localizedDescription` —
                // some SwiftData errors echo constraint values, which
                // could embed the provider tag on future schema drift.
                Self.logger.error("routing_signal_save_failed category=\(String(describing: type(of: error)), privacy: .public)")
                throw error
            }
        }.value
    }

    /// Retro-write `accepted` on the most recent `RoutingSignalEntry`
    /// matching `kind` (best-effort). Called from `ActiveWorkoutView`
    /// (substitute apply / cancel) and `AIChatView` (regenerate / normal
    /// finish). No-op if no matching row exists yet — the router's
    /// detached write may still be in flight.
    ///
    /// Runs off the caller's actor via `Task.detached` on a fresh
    /// `ModelContext`. Any thrown error is swallowed with a category-only
    /// os_log line so this call chain can never stall or crash a UI code
    /// path.
    public func updateLatestAccepted(kind: AITaskKind, accepted: Bool) {
        let container = self.container
        let kindRaw = kind.rawValue
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<RoutingSignalEntry>(
                predicate: #Predicate { $0.kind == kindRaw },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            do {
                var descriptorWithLimit = descriptor
                descriptorWithLimit.fetchLimit = 1
                guard let latest = try context.fetch(descriptorWithLimit).first else {
                    return
                }
                latest.accepted = accepted
                try context.save()
            } catch {
                Self.logger.error("routing_signal_accepted_update_failed category=\(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    // MARK: - Authorization revocation

    /// Called from `HealthDataCache.handleAuthorizationRevoked` (MY-1381
    /// 追加需求). Deletes every `RoutingSignalEntry` in the local Telemetry
    /// `.none` partition — routing signals may reflect calls that ingested
    /// HealthKit-derived context, so 宪法 I demands they leave the device
    /// alongside the health caches.
    ///
    /// Logs are category-only. No signal payload, no counts of any
    /// health-value derivative, no failure message body — see the parent
    /// package's red_line "健康数值禁止进任何日志".
    public func purgeOnAuthorizationRevoked() async throws {
        let container = self.container
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            do {
                try context.delete(model: RoutingSignalEntry.self)
                try context.save()
                Self.logger.info("routing_signal_entries_purged")
            } catch {
                Self.logger.error("routing_signal_purge_failed category=\(String(describing: type(of: error)), privacy: .public)")
                throw error
            }
        }.value
    }
}
