import Foundation
import SwiftData
import Testing
@testable import VitalModels

@Suite("BanditArmSnapshot Tests")
struct BanditArmSnapshotTests {

    // MARK: - Sendable / value-type conformance

    /// Compile-time proof that `BanditArmKey` and `BanditArmStateSnapshot` are
    /// Sendable. If either loses `Sendable`, this generic call will fail to compile.
    @Test("BanditArmKey and BanditArmStateSnapshot are Sendable at compile time")
    func sendableConformance() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        let key = BanditArmKey(kind: "chat", deviceTier: "cloudOnly", provider: "openai")
        let snap = BanditArmStateSnapshot(key: key, count: 1, rewardSum: 0.5, updatedAt: Date(timeIntervalSince1970: 100))
        _ = requireSendable(key)
        _ = requireSendable(snap)
    }

    // MARK: - Value semantics

    @Test("BanditArmKey Hashable/Equatable across identical fields")
    func keyEquality() {
        let a = BanditArmKey(kind: "chat", deviceTier: "cloudOnly", provider: "openai")
        let b = BanditArmKey(kind: "chat", deviceTier: "cloudOnly", provider: "openai")
        let c = BanditArmKey(kind: "chat", deviceTier: "cloudOnly", provider: "anthropic")
        #expect(a == b)
        #expect(a != c)
        #expect(Set([a, b, c]).count == 2)
    }

    @Test("Snapshot is Codable round-trip stable")
    func snapshotCodableRoundTrip() throws {
        let snap = BanditArmStateSnapshot(
            key: BanditArmKey(kind: "trainingAdvice", deviceTier: "onDeviceCapable", provider: "onDevice"),
            count: 5,
            rewardSum: 2.25,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(BanditArmStateSnapshot.self, from: data)
        #expect(decoded == snap)
    }

    // MARK: - Reward accumulation on the Sendable value

    @Test("adding(reward:at:) increments count by 1 and adds reward")
    func addingRewardAccumulates() {
        let key = BanditArmKey(kind: "chat", deviceTier: "cloudOnly", provider: "openai")
        let t0 = Date(timeIntervalSince1970: 0)
        let start = BanditArmStateSnapshot.initial(key: key, at: t0)
        let updated = start
            .adding(reward: 0.5, at: Date(timeIntervalSince1970: 1))
            .adding(reward: 1.0, at: Date(timeIntervalSince1970: 2))
            .adding(reward: 0.25, at: Date(timeIntervalSince1970: 3))
        #expect(updated.count == 3)
        #expect(updated.rewardSum == 1.75)
        #expect(updated.updatedAt == Date(timeIntervalSince1970: 3))
        // Original untouched — value semantics.
        // swiftlint:disable:next empty_count
        #expect(start.count == 0)
        #expect(start.rewardSum == 0)
    }

    // MARK: - Bridge: Entry <-> Snapshot

    @Test("Entry.init(snapshot:) mirrors all six fields")
    func entryFromSnapshotMirrorsFields() {
        let snap = BanditArmStateSnapshot(
            key: BanditArmKey(kind: "chat", deviceTier: "cloudOnly", provider: "openai"),
            count: 7,
            rewardSum: 3.5,
            updatedAt: Date(timeIntervalSince1970: 42)
        )
        let entry = BanditArmStateEntry(snapshot: snap)
        #expect(entry.kind == "chat")
        #expect(entry.deviceTier == "cloudOnly")
        #expect(entry.provider == "openai")
        #expect(entry.count == 7)
        #expect(entry.rewardSum == 3.5)
        #expect(entry.updatedAt == Date(timeIntervalSince1970: 42))
    }

    @Test("entry.snapshot() → Snapshot round-trip preserves identity + counters")
    func entrySnapshotRoundTrip() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let original = BanditArmStateSnapshot(
            key: BanditArmKey(kind: "trainingAdvice", deviceTier: "onDeviceCapable", provider: "onDevice"),
            count: 4,
            rewardSum: 1.5,
            updatedAt: Date(timeIntervalSince1970: 999)
        )
        let entry = BanditArmStateEntry(snapshot: original)
        context.insert(entry)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BanditArmStateEntry>())
        let live = try #require(fetched.first)
        let snap = live.snapshot()
        #expect(snap == original)
    }

    @Test("entry.apply(_:) writes counters + updatedAt without changing identity")
    func entryApplyUpdatesCountersOnly() throws {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let context = ModelContext(container)

        let key = BanditArmKey(kind: "chat", deviceTier: "cloudOnly", provider: "openai")
        let seed = BanditArmStateSnapshot.initial(key: key, at: Date(timeIntervalSince1970: 0))
        let entry = BanditArmStateEntry(snapshot: seed)
        context.insert(entry)
        try context.save()

        let updated = seed.adding(reward: 0.75, at: Date(timeIntervalSince1970: 10))
        entry.apply(updated)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<BanditArmStateEntry>())
        let live = try #require(fetched.first)
        #expect(live.count == 1)
        #expect(live.rewardSum == 0.75)
        #expect(live.updatedAt == Date(timeIntervalSince1970: 10))
        // Identity fields unchanged.
        #expect(live.kind == "chat")
        #expect(live.deviceTier == "cloudOnly")
        #expect(live.provider == "openai")
    }

    // MARK: - Documentation: no `@unchecked Sendable` on the @Model

    @Test("BanditArmStateEntry has no unchecked Sendable conformance — bridge relies on snapshot()")
    func entryDoesNotAdvertiseSendable() {
        // This test is intentionally a documentation guard: it names the invariant
        // that BanditArmStateEntry (a mutable `@Model` class) MUST NOT be marked
        // `@unchecked Sendable`. AIService-facing code crosses the boundary via
        // `BanditArmStateSnapshot` (which IS Sendable) instead. Enforcement is via
        // the source review — if the entry ever adopts `Sendable` this suite still
        // passes, and reviewers must reject the diff on the source rule.
        //
        // We assert the Sendable value type carries the arm's mutable counters, so
        // no caller has an excuse to hold the @Model across an actor boundary.
        let key = BanditArmKey(kind: "chat", deviceTier: "cloudOnly", provider: "openai")
        let snap = BanditArmStateSnapshot.initial(key: key, at: Date(timeIntervalSince1970: 0))
        #expect(snap.key == key)
        // swiftlint:disable:next empty_count
        #expect(snap.count == 0)
        #expect(snap.rewardSum == 0)
    }
}
