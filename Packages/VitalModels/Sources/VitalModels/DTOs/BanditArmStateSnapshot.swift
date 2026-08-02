import Foundation

/// Sendable, value-type snapshot of a bandit arm's mutable state.
///
/// Purpose: cross the actor boundary between the SwiftData-owned
/// `BanditArmStateEntry` (which must stay on its `ModelContext`) and the AIService-owned
/// bandit selection / update logic. The bandit reads a snapshot, computes new counters
/// off-thread, then hands a fresh snapshot back to a `@ModelActor` (or MainActor context)
/// which applies it to the persistent `BanditArmStateEntry`.
///
/// `key` identifies the arm; the remaining fields mirror `BanditArmStateEntry`'s
/// mutable counters. Immutable by design — mutation goes through
/// `withUpdated(...)` / `applying(_:)` to preserve the immutable/value discipline.
public struct BanditArmStateSnapshot: Hashable, Sendable, Codable {
    public let key: BanditArmKey
    public let count: Int
    public let rewardSum: Double
    public let updatedAt: Date

    public init(
        key: BanditArmKey,
        count: Int,
        rewardSum: Double,
        updatedAt: Date
    ) {
        self.key = key
        self.count = count
        self.rewardSum = rewardSum
        self.updatedAt = updatedAt
    }

    /// Returns a new snapshot with `count += 1` and `rewardSum += reward`.
    /// Callers pass the new `updatedAt` explicitly to keep the type deterministic.
    public func adding(reward: Double, at date: Date) -> BanditArmStateSnapshot {
        BanditArmStateSnapshot(
            key: key,
            count: count + 1,
            rewardSum: rewardSum + reward,
            updatedAt: date
        )
    }

    /// Prior-seeded initial arm for cold start; `Day-1 == static policy` per FR-013.
    public static func initial(key: BanditArmKey, at date: Date) -> BanditArmStateSnapshot {
        BanditArmStateSnapshot(key: key, count: 0, rewardSum: 0, updatedAt: date)
    }
}

// MARK: - BanditArmStateEntry <-> Snapshot bridge

extension BanditArmStateEntry {
    /// Convenience initializer that lifts a Sendable snapshot into a fresh `@Model`
    /// instance. Must be called from the actor / context that owns the
    /// `ModelContext` the entry will be inserted into.
    public convenience init(snapshot: BanditArmStateSnapshot) {
        self.init(
            kind: snapshot.key.kind,
            deviceTier: snapshot.key.deviceTier,
            provider: snapshot.key.provider,
            count: snapshot.count,
            rewardSum: snapshot.rewardSum,
            updatedAt: snapshot.updatedAt
        )
    }

    /// Read-only snapshot of the current entry state. Callers on the entry's context
    /// use this to hand a Sendable value to code that must not touch the `@Model`.
    ///
    /// This is the only sanctioned way for AIService-facing code to observe an arm's
    /// state without importing SwiftData or holding a live `@Model` reference.
    public func snapshot() -> BanditArmStateSnapshot {
        BanditArmStateSnapshot(
            key: BanditArmKey(kind: kind, deviceTier: deviceTier, provider: provider),
            count: count,
            rewardSum: rewardSum,
            updatedAt: updatedAt
        )
    }

    /// Applies mutable counters from a snapshot onto this entry. The `key` fields
    /// (`kind`/`deviceTier`/`provider`) are the identity of the arm and are asserted
    /// to match; identity is never mutated after insert.
    ///
    /// Precondition: `snapshot.key` matches this entry's `(kind, deviceTier, provider)`.
    /// Callers upstream (bandit repository) must have looked this entry up by that key.
    public func apply(_ snapshot: BanditArmStateSnapshot) {
        precondition(
            snapshot.key.kind == kind
                && snapshot.key.deviceTier == deviceTier
                && snapshot.key.provider == provider,
            "BanditArmStateSnapshot key must match entry identity"
        )
        count = snapshot.count
        rewardSum = snapshot.rewardSum
        updatedAt = snapshot.updatedAt
    }
}
