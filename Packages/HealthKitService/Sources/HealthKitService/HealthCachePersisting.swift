import Foundation

public struct PersistedAvailableTypes: Sendable {
    public let typeRawValues: Set<String>
    public let fetchedAt: Date

    public init(typeRawValues: Set<String>, fetchedAt: Date) {
        self.typeRawValues = typeRawValues
        self.fetchedAt = fetchedAt
    }
}

public struct PersistedCacheEntry: Sendable {
    public let sampleType: String
    public let dataPointsData: Data
    public let fetchedAt: Date
    public let coveredRangeStart: Date?
    public let coveredRangeEnd: Date?

    public init(
        sampleType: String,
        dataPointsData: Data,
        fetchedAt: Date,
        coveredRangeStart: Date?,
        coveredRangeEnd: Date?
    ) {
        self.sampleType = sampleType
        self.dataPointsData = dataPointsData
        self.fetchedAt = fetchedAt
        self.coveredRangeStart = coveredRangeStart
        self.coveredRangeEnd = coveredRangeEnd
    }
}

public protocol HealthCachePersisting: Sendable {
    func loadAll() async throws -> [PersistedCacheEntry]
    func load(sampleType: String) async throws -> PersistedCacheEntry?
    func upsert(_ entry: PersistedCacheEntry) async throws
    func deleteAll() async throws

    func loadAvailableTypes() async throws -> PersistedAvailableTypes?
    func saveAvailableTypes(_ entry: PersistedAvailableTypes) async throws
    func deleteAvailableTypes() async throws
}

/// Cross-package purge hook invoked from `HealthDataCache.handleAuthorizationRevoked`
/// (see MY-1381 追加需求 comment). HealthKitService owns HealthKit-derived
/// caches; it does NOT know about `VitalModels.RoutingSignalEntry` (would
/// invert the layer dependency: this package depends_on VitalModels but a
/// `RoutingSignalEntry`-shaped API here would drag Telemetry-partition
/// storage into HealthKit's domain). Instead the app target conforms an
/// object to this protocol and injects it — spec 019 Stage 3c wires
/// `RoutingSignalStore` as the conformer.
///
/// The revoke path (constitution I / HealthKitService red_line
/// "权限撤销即完整清除") calls `purge()` best-effort. Implementations must
/// throw on unrecoverable failure so the cache logger can record a
/// category-only error (no health values, no signal payload — that's the
/// same red_line).
public protocol AuthorizationRevocationHandling: Sendable {
    /// Purge any device-local data derived from HealthKit access. Called
    /// exactly once per revoke event. MUST be idempotent (revoke may fire
    /// repeatedly) and MUST NOT surface HealthKit values in its own log
    /// output.
    func purgeOnAuthorizationRevoked() async throws
}

