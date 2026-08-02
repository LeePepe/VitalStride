import Foundation
import Testing
@testable import HealthKitService

// MY-1381 追加需求 — Verify `HealthDataCache.handleAuthorizationRevoked`
// invokes every injected `AuthorizationRevocationHandling` conformer.
// The app target uses this to purge `RoutingSignalEntry` from the
// Telemetry `.none` partition when HealthKit access is revoked (宪法 I).
struct AuthorizationRevocationHandlerTests {

    final class SpyHandler: AuthorizationRevocationHandling, @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        private let shouldThrow: Bool

        init(shouldThrow: Bool = false) {
            self.shouldThrow = shouldThrow
        }

        var callCount: Int {
            lock.withLock { _callCount }
        }

        func purgeOnAuthorizationRevoked() async throws {
            lock.withLock { _callCount += 1 }
            if shouldThrow {
                throw NSError(domain: "test", code: 1)
            }
        }
    }

    @Test("handleAuthorizationRevoked invokes every registered revocation handler")
    func revokeInvokesAllHandlers() async {
        let mock = MockHealthDataProvider()
        let a = SpyHandler()
        let b = SpyHandler()
        let cache = HealthDataCache(
            dataProvider: mock,
            revocationHandlers: [a, b]
        )

        await cache.handleAuthorizationRevoked()

        #expect(a.callCount == 1)
        #expect(b.callCount == 1)
    }

    @Test("handleAuthorizationRevoked continues past a thrown handler error")
    func revokeSurvivesHandlerError() async {
        let mock = MockHealthDataProvider()
        let thrower = SpyHandler(shouldThrow: true)
        let survivor = SpyHandler()
        let cache = HealthDataCache(
            dataProvider: mock,
            revocationHandlers: [thrower, survivor]
        )

        await cache.handleAuthorizationRevoked()

        // Both handlers must run even if the first throws — the cache's
        // revoke path is best-effort per handler (宪法 I: full-clear on
        // revoke is required; a single subsystem failure MUST NOT block
        // the others).
        #expect(thrower.callCount == 1)
        #expect(survivor.callCount == 1)
    }

    @Test("Cache with no handlers registered behaves as before")
    func revokeWithNoHandlersIsBackwardCompatible() async {
        let mock = MockHealthDataProvider()
        let cache = HealthDataCache(dataProvider: mock)

        // Simply exercising the code path — no crash / assertion failure
        // means the default empty handler list is respected.
        await cache.handleAuthorizationRevoked()
        #expect(true)
    }
}
