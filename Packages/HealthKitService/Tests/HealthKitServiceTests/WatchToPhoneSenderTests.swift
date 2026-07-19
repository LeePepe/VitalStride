import Testing
import Foundation
@testable import HealthKitService

// MARK: - Tests for WatchToPhoneSending abstraction (MY-1282)

@Suite("WatchToPhoneSending")
struct WatchToPhoneSendingTests {

    @Test("NoopWatchToPhoneSender is never reachable")
    func noopNotReachable() {
        let sender = NoopWatchToPhoneSender()
        #expect(sender.isReachable == false)
    }

    @Test("NoopWatchToPhoneSender.send throws notSupported")
    func noopSendThrowsNotSupported() {
        let sender = NoopWatchToPhoneSender()
        let payload = LiveHeartRatePayload(
            bpm: 120,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceName: "test"
        )
        do {
            try sender.send(.liveHeartRate(payload))
            Issue.record("expected throw from NoopWatchToPhoneSender.send")
        } catch WatchConnectivityBridgeError.notSupported {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}

// MARK: - RecordingSender captures pushed messages for wiring tests.

final class RecordingWatchToPhoneSender: WatchToPhoneSending, @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [WatchConnectivityMessage] = []
    private var _reachable: Bool

    init(reachable: Bool = true) {
        self._reachable = reachable
    }

    var isReachable: Bool {
        lock.withLock { _reachable }
    }

    func setReachable(_ value: Bool) {
        lock.withLock { _reachable = value }
    }

    var sentMessages: [WatchConnectivityMessage] {
        lock.withLock { _messages }
    }

    func send(_ message: WatchConnectivityMessage) throws {
        let reachable = lock.withLock { _reachable }
        guard reachable else {
            throw WatchConnectivityBridgeError.notReachable
        }
        lock.withLock { _messages.append(message) }
    }
}

@Suite("RecordingWatchToPhoneSender")
struct RecordingWatchToPhoneSenderTests {

    @Test("Records send when reachable")
    func recordsSendWhenReachable() throws {
        let sender = RecordingWatchToPhoneSender(reachable: true)
        let payload = LiveHeartRatePayload(
            bpm: 88,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceName: "Apple Watch"
        )
        try sender.send(.liveHeartRate(payload))
        #expect(sender.sentMessages.count == 1)
        if case .liveHeartRate(let recorded) = sender.sentMessages[0] {
            #expect(recorded.bpm == 88)
            #expect(recorded.sampleType == .heartRate)
        } else {
            Issue.record("expected .liveHeartRate message")
        }
    }

    @Test("Throws notReachable when unreachable and drops sample")
    func throwsWhenUnreachable() {
        let sender = RecordingWatchToPhoneSender(reachable: false)
        let payload = LiveHeartRatePayload(
            bpm: 88,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceName: nil
        )
        do {
            try sender.send(.liveHeartRate(payload))
            Issue.record("expected throw")
        } catch WatchConnectivityBridgeError.notReachable {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
        #expect(sender.sentMessages.isEmpty)
    }
}
