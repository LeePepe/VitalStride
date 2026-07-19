import Foundation
import os

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - WatchToPhoneSending
//
// Watch → iPhone sender abstraction (MY-1282). Injected into `WorkoutSessionManager`
// on watchOS so it can push realtime `LiveHeartRatePayload` samples (and, in
// future, `SetCompletedEvent`s) to the paired iPhone via the ADR-0010 Addendum
// WatchConnectivity contract owned by this package (`WatchConnectivityPayload`).
//
// Privacy §I: implementations MUST NOT log the HR bpm value — only sample type
// counts / delivery status. HR arrives as an opaque `WatchConnectivityMessage`
// after encoding, so the sender itself never has to look inside the payload.
//
// Concurrency:
//   * Protocol is Sendable — safe to hand into the actor/watchOS class.
//   * Default watchOS implementation follows the same
//     "checked-isolation + narrow `@unchecked Sendable` shim" pattern used by
//     `DefaultWatchConnectivitySessionProvider` on iOS (§Constitution II).

public protocol WatchToPhoneSending: Sendable {
    /// True when a live message can be delivered right now (counterpart
    /// awake + in-range). Time-critical HR samples are dropped when false;
    /// non-time-critical payloads may fall back to
    /// `updateApplicationContext` in the concrete impl.
    var isReachable: Bool { get }

    /// Encode + transport `message`. Throws `WatchConnectivityBridgeError`
    /// (`.notSupported` when WCSession unavailable / `.notReachable` when
    /// counterpart offline and message is time-critical).
    func send(_ message: WatchConnectivityMessage) throws
}

// MARK: - NoopWatchToPhoneSender

/// Used on platforms without WatchConnectivity (macOS, tests) and by
/// `WorkoutSessionManager` when no sender was injected. Every `send` throws
/// so the caller can distinguish "we tried but had no transport" from
/// "delivered".
public struct NoopWatchToPhoneSender: WatchToPhoneSending {
    public init() {}
    public var isReachable: Bool { false }
    public func send(_ message: WatchConnectivityMessage) throws {
        throw WatchConnectivityBridgeError.notSupported
    }
}

// MARK: - DefaultWatchToPhoneSender (watchOS)

#if canImport(WatchConnectivity) && os(watchOS)

/// Default watchOS-side WCSession-backed sender.
///
/// Activation:
///   * `WCSession.default` is activated on init and this instance is installed
///     as its delegate. Apple retains the delegate; we hold it via
///     `nonisolated(unsafe) let` on the shim following the same pattern as
///     `DefaultWatchConnectivitySessionProvider` on iOS.
///
/// Transport routing:
///   * `.liveHeartRate` uses `sendMessage` (time-critical, dropped when
///     unreachable — HR must never queue and replay stale values §I).
///   * `.setCompleted` uses `sendMessage` if reachable, else falls back to
///     `updateApplicationContext` (latest-wins) so the event isn't lost.
///   * `.workoutState` / `.watchScreenConfig` are reverse-direction on this
///     watchOS sender (iPhone is the SENDER of those). We still route them
///     via `updateApplicationContext` for forward-compatibility, but they
///     should not be posted from watch code paths in this task's scope.
public final class DefaultWatchToPhoneSender: NSObject, WatchToPhoneSending, @unchecked Sendable {
    private let logger: Logger

    public override init() {
        self.logger = Logger(subsystem: "com.vitalstride", category: "WatchToPhoneSender")
        super.init()
        activate()
    }

    private func activate() {
        guard WCSession.isSupported() else {
            logger.info("watch_wcsession_unsupported")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    public var isReachable: Bool {
        guard WCSession.isSupported() else { return false }
        return WCSession.default.isReachable
    }

    public func send(_ message: WatchConnectivityMessage) throws {
        guard WCSession.isSupported() else {
            throw WatchConnectivityBridgeError.notSupported
        }
        let dict = try WatchConnectivityCodec.encodeDictionary(message)
        let reachable = WCSession.default.isReachable

        switch message {
        case .liveHeartRate:
            // Time-critical + no persistence value: drop when unreachable
            // (never log the value §I; kind counter only).
            guard reachable else {
                logger.info("watch_send_dropped kind=liveHeartRate reason=unreachable")
                throw WatchConnectivityBridgeError.notReachable
            }
            WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: nil)
            logger.info("watch_send_ok kind=liveHeartRate transport=message")

        case .setCompleted:
            if reachable {
                WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: nil)
                logger.info("watch_send_ok kind=setCompleted transport=message")
            } else {
                do {
                    try WCSession.default.updateApplicationContext(dict)
                    logger.info("watch_send_ok kind=setCompleted transport=applicationContext")
                } catch {
                    logger.error(
                        "watch_send_failed kind=setCompleted error=\(error.localizedDescription, privacy: .private)"
                    )
                    throw error
                }
            }

        case .workoutState, .watchScreenConfig:
            // Reverse direction from the watch's perspective, but keep a
            // safe fallback so future callers don't crash.
            do {
                try WCSession.default.updateApplicationContext(dict)
                logger.info("watch_send_ok kind=reverseDirection transport=applicationContext")
            } catch {
                logger.error(
                    "watch_send_failed kind=reverseDirection error=\(error.localizedDescription, privacy: .private)"
                )
                throw error
            }
        }
    }
}

extension DefaultWatchToPhoneSender: WCSessionDelegate {
    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            logger.error(
                "watch_wcsession_activation_failed error=\(error.localizedDescription, privacy: .private)"
            )
        } else {
            logger.info("watch_wcsession_activated state=\(activationState.rawValue, privacy: .public)")
        }
    }
}

#endif // canImport(WatchConnectivity) && os(watchOS)
