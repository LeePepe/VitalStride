import Foundation
import os

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

// MARK: - Abstraction over WCSession (for testability)
//
// WCSession itself isn't directly injectable/mockable in tests because
// WCSession.default is a singleton coupled to the process. We funnel our
// dependency on it through this protocol so tests can drive the bridge with
// a synthetic session that doesn't require a real Watch pairing.

public protocol WatchConnectivitySessionProviding: AnyObject, Sendable {
    var isSupported: Bool { get }
    var isPaired: Bool { get }
    var isWatchAppInstalled: Bool { get }
    var isReachable: Bool { get }

    func activate()
    func setDelegate(_ delegate: WatchConnectivitySessionDelegateHandling)

    /// Send a low-latency payload that requires the counterpart to be reachable.
    func sendMessage(_ dictionary: [String: Any]) throws

    /// Update the latest-wins application context (delivered even when
    /// counterpart is unreachable; overwrites prior value).
    func updateApplicationContext(_ dictionary: [String: Any]) throws
}

/// Callbacks the bridge cares about. Everything is `[String: Any]` opaque —
/// this protocol is intentionally decoupled from WatchConnectivity types so
/// tests don't have to fabricate `WCSessionActivationState`.
public protocol WatchConnectivitySessionDelegateHandling: AnyObject, Sendable {
    func sessionDidChangeReachability(isReachable: Bool)
    func sessionDidReceiveMessage(_ dictionary: [String: Any])
    func sessionDidReceiveApplicationContext(_ dictionary: [String: Any])
    func sessionDidActivate(
        isSupported: Bool,
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isReachable: Bool,
        error: (any Error)?
    )
}

// MARK: - PhoneWorkoutSessionManager (iOS receive side)
//
// Responsibilities on iOS:
//   1. Own an activated `WCSession` and route incoming payloads to typed
//      AsyncStreams (`observeLiveWorkoutHeartRate`, `observeSetCompleted`)
//      and connection-state changes to `observeConnectionState`.
//   2. Push outgoing state (`WorkoutStateSnapshot`, `WatchScreenConfig`) to
//      the watch via `updateApplicationContext` (latest-wins).
//   3. Never log the HR value; only sample type + count + time range.
//
// startSession / endSession control WHETHER we forward HR into the observer
// stream. If a session is not active, incoming HR messages are dropped (still
// no crash, still no log of value).

public final class PhoneWorkoutSessionManager: NSObject, WorkoutSessionManaging, @unchecked Sendable {
    private let session: any WatchConnectivitySessionProviding
    private let logger: Logger
    private let lock = NSLock()

    private var isSessionActive = false
    private var hrContinuations: [UUID: AsyncStream<LiveHeartRatePayload>.Continuation] = [:]
    private var connectionContinuations: [UUID: AsyncStream<WatchConnectionState>.Continuation] = [:]
    private var setCompletedContinuations: [UUID: AsyncStream<SetCompletedEvent>.Continuation] = [:]
    private var lastConnectionState: WatchConnectionState = .unsupported
    private var forwardedHRCount = 0

    public init(session: any WatchConnectivitySessionProviding) {
        self.session = session
        self.logger = Logger(subsystem: "com.vitalstride", category: "PhoneWorkoutSession")
        super.init()
        self.session.setDelegate(self)
        self.session.activate()
        self.updateConnectionState(computeConnectionState(activated: false))
    }

    // MARK: WorkoutSessionManaging

    public func startSession() async {
        let wasActive = lock.withLock { () -> Bool in
            let previous = isSessionActive
            isSessionActive = true
            forwardedHRCount = 0
            return previous
        }
        if wasActive {
            logger.info("phone_workout_session_start_skipped reason=already_active")
        } else {
            logger.info("phone_workout_session_started")
        }
    }

    @discardableResult
    public func endSession(save: Bool) async -> String? {
        let (wasActive, count) = lock.withLock { () -> (Bool, Int) in
            let previous = isSessionActive
            let count = forwardedHRCount
            isSessionActive = false
            forwardedHRCount = 0
            return (previous, count)
        }
        if wasActive {
            logger.info(
                "phone_workout_session_ended saved=\(save, privacy: .public) hrSampleCount=\(count, privacy: .public)"
            )
        }
        // iPhone side does not own the HKWorkout; return nil.
        return nil
    }

    public func observeLiveWorkoutHeartRate() -> AsyncStream<LiveHeartRatePayload> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock { hrContinuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.hrContinuations[id] = nil }
            }
        }
    }

    public func observeConnectionState() -> AsyncStream<WatchConnectionState> {
        let id = UUID()
        let initialState = lock.withLock { lastConnectionState }
        return AsyncStream { continuation in
            self.lock.withLock { self.connectionContinuations[id] = continuation }
            continuation.yield(initialState)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.connectionContinuations[id] = nil }
            }
        }
    }

    public func observeSetCompleted() -> AsyncStream<SetCompletedEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.lock.withLock { self.setCompletedContinuations[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.withLock { self.setCompletedContinuations[id] = nil }
            }
        }
    }

    public func updateWorkoutState(_ snapshot: WorkoutStateSnapshot) async {
        do {
            let dict = try WatchConnectivityCodec.encodeDictionary(.workoutState(snapshot))
            try session.updateApplicationContext(dict)
            logger.info(
                "phone_workout_state_pushed setCount=\(snapshot.sets.count, privacy: .public) progress=\(snapshot.progress.completedSetCount, privacy: .public)/\(snapshot.progress.totalSetCount, privacy: .public)"
            )
        } catch {
            logger.error(
                "phone_workout_state_push_failed error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    public func updateWatchScreenConfig(_ config: WatchScreenConfig) async {
        do {
            let dict = try WatchConnectivityCodec.encodeDictionary(.watchScreenConfig(config))
            try session.updateApplicationContext(dict)
            logger.info(
                "phone_watch_screen_config_pushed preset=\(config.preset.rawValue, privacy: .public) modules=\(config.enabledModules.count, privacy: .public)"
            )
        } catch {
            logger.error(
                "phone_watch_screen_config_push_failed error=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    // MARK: Internal

    private func computeConnectionState(activated: Bool) -> WatchConnectionState {
        if !session.isSupported { return .unsupported }
        if !session.isPaired { return .notPaired }
        if !session.isWatchAppInstalled { return .notInstalled }
        if !session.isReachable { return .unreachable }
        return .reachable
    }

    private func updateConnectionState(_ new: WatchConnectionState) {
        let continuations = lock.withLock { () -> [AsyncStream<WatchConnectionState>.Continuation] in
            guard new != lastConnectionState else { return [] }
            lastConnectionState = new
            return Array(connectionContinuations.values)
        }
        for continuation in continuations {
            continuation.yield(new)
        }
    }

    private func handleDecoded(_ message: WatchConnectivityMessage) {
        switch message {
        case .liveHeartRate(let payload):
            handleHRSample(payload)
        case .setCompleted(let event):
            handleSetCompleted(event)
        case .workoutState, .watchScreenConfig:
            // These are iPhone → watch only. Receiving one means the peer
            // echoed or misused the channel; drop it, don't crash, don't log
            // the payload.
            logger.info("phone_workout_bridge_ignored_reverse_payload")
        }
    }

    private func handleHRSample(_ payload: LiveHeartRatePayload) {
        guard payload.isPhysiologicallyPlausible else {
            // Reject impossible values; do NOT log the value itself.
            logger.info("phone_workout_hr_rejected reason=out_of_range")
            return
        }
        let continuations: [AsyncStream<LiveHeartRatePayload>.Continuation] = lock.withLock {
            guard isSessionActive else { return [] }
            forwardedHRCount += 1
            return Array(hrContinuations.values)
        }
        guard !continuations.isEmpty else {
            // No active session or no subscribers: silently drop, don't log.
            return
        }
        for continuation in continuations {
            continuation.yield(payload)
        }
        // Privacy §I: log sample type + count only, never bpm value.
        logger.info("phone_workout_hr_forwarded sampleType=heartRate count=1")
    }

    private func handleSetCompleted(_ event: SetCompletedEvent) {
        let continuations = lock.withLock { Array(setCompletedContinuations.values) }
        for continuation in continuations {
            continuation.yield(event)
        }
        logger.info("phone_workout_set_completed workoutID=\(event.workoutID.uuidString, privacy: .public)")
    }
}

// MARK: - Delegate conformance

extension PhoneWorkoutSessionManager: WatchConnectivitySessionDelegateHandling {
    public func sessionDidChangeReachability(isReachable: Bool) {
        let state = computeConnectionState(activated: true)
        updateConnectionState(state)
    }

    public func sessionDidReceiveMessage(_ dictionary: [String: Any]) {
        do {
            let message = try WatchConnectivityCodec.decodeDictionary(dictionary)
            handleDecoded(message)
        } catch {
            logger.info(
                "phone_workout_bridge_decode_failed source=message reason=\(String(describing: error), privacy: .public)"
            )
        }
    }

    public func sessionDidReceiveApplicationContext(_ dictionary: [String: Any]) {
        // application-context is currently only iPhone→watch, but decode
        // defensively in case future work adds watch→iPhone latest-wins state.
        do {
            let message = try WatchConnectivityCodec.decodeDictionary(dictionary)
            handleDecoded(message)
        } catch {
            logger.info(
                "phone_workout_bridge_decode_failed source=applicationContext reason=\(String(describing: error), privacy: .public)"
            )
        }
    }

    public func sessionDidActivate(
        isSupported: Bool,
        isPaired: Bool,
        isWatchAppInstalled: Bool,
        isReachable: Bool,
        error: (any Error)?
    ) {
        if let error {
            logger.error(
                "phone_workout_bridge_activation_failed error=\(error.localizedDescription, privacy: .private)"
            )
        }
        let state = computeConnectionState(activated: true)
        updateConnectionState(state)
    }
}

// MARK: - Default WCSession-backed provider (iOS only)

#if canImport(WatchConnectivity) && os(iOS)

public final class DefaultWatchConnectivitySessionProvider: NSObject, WatchConnectivitySessionProviding, @unchecked Sendable {
    private let session: WCSession
    private let lock = NSLock()
    private weak var handler: (any WatchConnectivitySessionDelegateHandling)?

    public override init() {
        self.session = WCSession.default
        super.init()
    }

    public var isSupported: Bool { WCSession.isSupported() }
    public var isPaired: Bool { session.isPaired }
    public var isWatchAppInstalled: Bool { session.isWatchAppInstalled }
    public var isReachable: Bool { session.isReachable }

    public func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    public func setDelegate(_ delegate: any WatchConnectivitySessionDelegateHandling) {
        lock.withLock { handler = delegate }
    }

    public func sendMessage(_ dictionary: [String: Any]) throws {
        guard session.isReachable else { throw WatchConnectivityBridgeError.notReachable }
        session.sendMessage(dictionary, replyHandler: nil, errorHandler: nil)
    }

    public func updateApplicationContext(_ dictionary: [String: Any]) throws {
        try session.updateApplicationContext(dictionary)
    }
}

extension DefaultWatchConnectivitySessionProvider: WCSessionDelegate {
    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let handler = lock.withLock { self.handler }
        handler?.sessionDidActivate(
            isSupported: WCSession.isSupported(),
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable,
            error: error
        )
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {
        let handler = lock.withLock { self.handler }
        handler?.sessionDidChangeReachability(isReachable: session.isReachable)
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        // Per Apple guidance re-activate to allow switching watches.
        WCSession.default.activate()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        let handler = lock.withLock { self.handler }
        handler?.sessionDidChangeReachability(isReachable: session.isReachable)
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let handler = lock.withLock { self.handler }
        handler?.sessionDidReceiveMessage(message)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let handler = lock.withLock { self.handler }
        handler?.sessionDidReceiveApplicationContext(applicationContext)
    }
}

#endif // canImport(WatchConnectivity) && os(iOS)

public enum WatchConnectivityBridgeError: Error, Sendable, Equatable {
    case notReachable
    case notSupported
}
