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

// MARK: - PhoneWorkoutSessionManager (iOS receive side, actor-isolated)
//
// Responsibilities on iOS:
//   1. Own an activated `WCSession` and route incoming payloads to typed
//      AsyncStreams (`observeLiveWorkoutHeartRate`, `observeSetCompleted`)
//      and connection-state changes to `observeConnectionState`.
//   2. Push outgoing state (`WorkoutStateSnapshot`, `WatchScreenConfig`) to
//      the watch via `updateApplicationContext` (latest-wins).
//   3. Never log the HR value; only sample type + count + time range.
//
// Channel-direction enforcement (§ADR-0010 Addendum contract):
//   - `sessionDidReceiveMessage`  MUST carry watch→iPhone payloads only
//     (`.liveHeartRate`, `.setCompleted`). WorkoutState / WatchScreenConfig
//     arriving here are reverse-direction bugs — dropped, logged, never
//     forwarded to subscribers.
//   - `sessionDidReceiveApplicationContext`  is unused by us as receiver
//     (we're the sender of state/config). Anything arriving here is
//     dropped. HR / SetCompleted on this channel are ALSO dropped as a
//     wrong-channel violation (per contract they must use sendMessage).
//
// Concurrency:
//   - Actor-isolated state. No `@unchecked Sendable`, no `NSLock`.
//   - Delegate callbacks arrive on Apple-owned threads via `nonisolated`
//     conformance methods that dispatch typed, Sendable messages into the
//     actor. `[String: Any]` never crosses the concurrency boundary — we
//     decode into `WatchConnectivityMessage` (Sendable) synchronously in
//     the nonisolated shim.
//
// startSession / endSession control WHETHER we forward HR into the observer
// stream. If a session is not active, incoming HR messages are dropped (still
// no crash, still no log of value).

public actor PhoneWorkoutSessionManager: WorkoutSessionManaging {
    private let session: any WatchConnectivitySessionProviding
    private nonisolated let logger: Logger

    private var isSessionActive = false
    private var hrContinuations: [UUID: AsyncStream<LiveHeartRatePayload>.Continuation] = [:]
    private var connectionContinuations: [UUID: AsyncStream<WatchConnectionState>.Continuation] = [:]
    private var setCompletedContinuations: [UUID: AsyncStream<SetCompletedEvent>.Continuation] = [:]
    private var lastConnectionState: WatchConnectionState = .unsupported
    private var forwardedHRCount = 0

    public init(session: any WatchConnectivitySessionProviding) {
        self.session = session
        self.logger = Logger(subsystem: "com.vitalstride", category: "PhoneWorkoutSession")
        // Compute initial connection state synchronously so observers get the
        // correct first value regardless of when the delegate's activation
        // callback later hops into the actor.
        if !session.isSupported {
            self.lastConnectionState = .unsupported
        } else if !session.isPaired {
            self.lastConnectionState = .notPaired
        } else if !session.isWatchAppInstalled {
            self.lastConnectionState = .notInstalled
        } else if !session.isReachable {
            self.lastConnectionState = .unreachable
        } else {
            self.lastConnectionState = .reachable
        }
        session.setDelegate(self)
        session.activate()
    }

    // MARK: WorkoutSessionManaging

    public func startSession() async {
        let wasActive = isSessionActive
        isSessionActive = true
        forwardedHRCount = 0
        if wasActive {
            logger.info("phone_workout_session_start_skipped reason=already_active")
        } else {
            logger.info("phone_workout_session_started")
        }
    }

    @discardableResult
    public func endSession(save: Bool) async -> String? {
        let wasActive = isSessionActive
        let count = forwardedHRCount
        isSessionActive = false
        forwardedHRCount = 0
        if wasActive {
            logger.info(
                "phone_workout_session_ended saved=\(save, privacy: .public) hrSampleCount=\(count, privacy: .public)"
            )
        }
        // iPhone side does not own the HKWorkout; return nil.
        return nil
    }

    public func observeLiveWorkoutHeartRate() async -> AsyncStream<LiveHeartRatePayload> {
        let id = UUID()
        // Bounded newest-value buffering (§P1 review fix). HR is display-only;
        // if a slow subscriber falls behind, we prefer to render the newest
        // value rather than replay a stale queue.
        let (stream, continuation) = AsyncStream<LiveHeartRatePayload>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        hrContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeHRContinuation(id) }
        }
        return stream
    }

    public func observeConnectionState() async -> AsyncStream<WatchConnectionState> {
        let id = UUID()
        let initialState = lastConnectionState
        // Bounded newest-value: connection-state is idempotent; only the
        // latest value ever matters to UI.
        let (stream, continuation) = AsyncStream<WatchConnectionState>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        connectionContinuations[id] = continuation
        continuation.yield(initialState)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeConnectionContinuation(id) }
        }
        return stream
    }

    public func observeSetCompleted() async -> AsyncStream<SetCompletedEvent> {
        let id = UUID()
        // Explicit queue semantics: `.unbounded` — every set-completion event
        // MUST reach the reconciler. iPhone is source of truth; dropping a
        // watch confirmation would leave the two sides out of sync.
        let (stream, continuation) = AsyncStream<SetCompletedEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
        setCompletedContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSetCompletedContinuation(id) }
        }
        return stream
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

    // MARK: Actor-internal helpers

    private func removeHRContinuation(_ id: UUID) {
        hrContinuations[id] = nil
    }

    private func removeConnectionContinuation(_ id: UUID) {
        connectionContinuations[id] = nil
    }

    private func removeSetCompletedContinuation(_ id: UUID) {
        setCompletedContinuations[id] = nil
    }

    private func computeConnectionState() -> WatchConnectionState {
        if !session.isSupported { return .unsupported }
        if !session.isPaired { return .notPaired }
        if !session.isWatchAppInstalled { return .notInstalled }
        if !session.isReachable { return .unreachable }
        return .reachable
    }

    fileprivate func handleReachabilityChange() {
        updateConnectionState(computeConnectionState())
    }

    fileprivate func handleActivationCompleted() {
        updateConnectionState(computeConnectionState())
    }

    private func updateConnectionState(_ new: WatchConnectionState) {
        guard new != lastConnectionState else { return }
        lastConnectionState = new
        for continuation in connectionContinuations.values {
            continuation.yield(new)
        }
    }

    // MARK: Channel-direction enforcement

    fileprivate func handleIncomingMessage(_ message: WatchConnectivityMessage) {
        switch message {
        case .liveHeartRate(let payload):
            handleHRSample(payload)
        case .setCompleted(let event):
            handleSetCompleted(event)
        case .workoutState:
            // Reverse direction — iPhone is the SENDER of workoutState.
            logger.info("phone_workout_bridge_ignored_reverse_payload channel=message kind=workoutState")
        case .watchScreenConfig:
            logger.info("phone_workout_bridge_ignored_reverse_payload channel=message kind=watchScreenConfig")
        }
    }

    fileprivate func handleIncomingApplicationContext(_ message: WatchConnectivityMessage) {
        switch message {
        case .workoutState:
            // Reverse direction — iPhone is the SENDER of workoutState.
            logger.info("phone_workout_bridge_ignored_reverse_payload channel=applicationContext kind=workoutState")
        case .watchScreenConfig:
            logger.info("phone_workout_bridge_ignored_reverse_payload channel=applicationContext kind=watchScreenConfig")
        case .liveHeartRate:
            // Wrong channel: per contract HR MUST arrive via sendMessage.
            // Drop silently (never crash, never log value).
            logger.info("phone_workout_bridge_wrong_channel expected=message actual=applicationContext kind=liveHeartRate")
        case .setCompleted:
            logger.info("phone_workout_bridge_wrong_channel expected=message actual=applicationContext kind=setCompleted")
        }
    }

    private func handleHRSample(_ payload: LiveHeartRatePayload) {
        // Physiological plausibility gate (already applied at codec.validate,
        // this is defence-in-depth for future callers).
        guard payload.isPhysiologicallyPlausible else {
            // Do NOT log the value itself (§I).
            logger.info("phone_workout_hr_rejected reason=out_of_range")
            return
        }
        guard isSessionActive, !hrContinuations.isEmpty else {
            // No active session or no subscribers: silently drop.
            return
        }
        forwardedHRCount += 1
        for continuation in hrContinuations.values {
            continuation.yield(payload)
        }
        // Privacy §I: log sample type + count only, never bpm value.
        logger.info("phone_workout_hr_forwarded sampleType=heartRate count=1")
    }

    private func handleSetCompleted(_ event: SetCompletedEvent) {
        for continuation in setCompletedContinuations.values {
            continuation.yield(event)
        }
        logger.info("phone_workout_set_completed workoutID=\(event.workoutID.uuidString, privacy: .public)")
    }
}

// MARK: - Delegate conformance (nonisolated bridge)
//
// The delegate callbacks arrive on the WCSession's private queue (or on the
// FakeWCSession's caller thread in tests). We keep them `nonisolated`, decode
// the `[String: Any]` payload synchronously into a `Sendable` message, and
// hop into the actor to update state. This is the standard Swift 6 pattern
// for bridging Apple ObjC-delegate boundaries into actor-isolated state.

extension PhoneWorkoutSessionManager: WatchConnectivitySessionDelegateHandling {
    public nonisolated func sessionDidChangeReachability(isReachable: Bool) {
        Task { await self.handleReachabilityChange() }
    }

    public nonisolated func sessionDidReceiveMessage(_ dictionary: [String: Any]) {
        // Decode outside the actor. `WatchConnectivityMessage` is Sendable,
        // so it crosses the boundary safely; `[String: Any]` does not.
        let decoded: WatchConnectivityMessage
        do {
            decoded = try WatchConnectivityCodec.decodeDictionary(dictionary)
        } catch {
            logger.info(
                "phone_workout_bridge_decode_failed source=message reason=\(String(describing: error), privacy: .public)"
            )
            return
        }
        Task { await self.handleIncomingMessage(decoded) }
    }

    public nonisolated func sessionDidReceiveApplicationContext(_ dictionary: [String: Any]) {
        let decoded: WatchConnectivityMessage
        do {
            decoded = try WatchConnectivityCodec.decodeDictionary(dictionary)
        } catch {
            logger.info(
                "phone_workout_bridge_decode_failed source=applicationContext reason=\(String(describing: error), privacy: .public)"
            )
            return
        }
        Task { await self.handleIncomingApplicationContext(decoded) }
    }

    public nonisolated func sessionDidActivate(
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
        Task { await self.handleActivationCompleted() }
    }
}

// MARK: - Default WCSession-backed provider (iOS only)
//
// Apple-SDK boundary wrapper for `WCSession`. This is the ONLY type in the
// bridge that keeps `@unchecked Sendable`, because:
//   1. `WCSession` is a non-Sendable Apple SDK singleton.
//   2. `WCSessionDelegate` is an `@objc` protocol requiring `NSObject`
//      inheritance, which Swift actors do not permit.
//   3. Delegate callbacks are dispatched by CoreFoundation on WCSession's
//      own serial queue — Apple already serialises them for us.
// Mutable state is confined to the `handlerBox` (an `OSAllocatedUnfairLock`,
// itself `Sendable`); all other stored properties are `let`. Sendable
// violations are impossible by construction. See ADR-0010 Addendum for the
// original boundary decision.

#if canImport(WatchConnectivity) && os(iOS)

public final class DefaultWatchConnectivitySessionProvider: NSObject, WatchConnectivitySessionProviding, @unchecked Sendable {
    private let session: WCSession
    private let handlerBox = OSAllocatedUnfairLock<HandlerBox>(initialState: HandlerBox())

    private struct HandlerBox: Sendable {
        weak var handler: (any WatchConnectivitySessionDelegateHandling)?
    }

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
        handlerBox.withLock { $0.handler = delegate }
    }

    public func sendMessage(_ dictionary: [String: Any]) throws {
        guard session.isReachable else { throw WatchConnectivityBridgeError.notReachable }
        session.sendMessage(dictionary, replyHandler: nil, errorHandler: nil)
    }

    public func updateApplicationContext(_ dictionary: [String: Any]) throws {
        try session.updateApplicationContext(dictionary)
    }

    private func currentHandler() -> (any WatchConnectivitySessionDelegateHandling)? {
        handlerBox.withLock { $0.handler }
    }
}

extension DefaultWatchConnectivitySessionProvider: WCSessionDelegate {
    public func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        currentHandler()?.sessionDidActivate(
            isSupported: WCSession.isSupported(),
            isPaired: session.isPaired,
            isWatchAppInstalled: session.isWatchAppInstalled,
            isReachable: session.isReachable,
            error: error
        )
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {
        currentHandler()?.sessionDidChangeReachability(isReachable: session.isReachable)
    }

    public func sessionDidDeactivate(_ session: WCSession) {
        // Per Apple guidance re-activate to allow switching watches.
        WCSession.default.activate()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        currentHandler()?.sessionDidChangeReachability(isReachable: session.isReachable)
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        currentHandler()?.sessionDidReceiveMessage(message)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        currentHandler()?.sessionDidReceiveApplicationContext(applicationContext)
    }
}

#endif // canImport(WatchConnectivity) && os(iOS)

public enum WatchConnectivityBridgeError: Error, Sendable, Equatable {
    case notReachable
    case notSupported
}
