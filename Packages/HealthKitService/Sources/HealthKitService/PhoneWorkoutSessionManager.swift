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
// Apple-SDK boundary wrapper for `WCSession`. This uses **checked** `Sendable`
// conformance with per-property `nonisolated(unsafe)` markers — NOT
// class-level `@unchecked Sendable`. The distinction matters (§Constitution II):
//
//   * `@unchecked Sendable` disables Sendable verification for the WHOLE type.
//   * `nonisolated(unsafe) let` on a specific property is a narrow, per-line
//     documented escape hatch that keeps the rest of the type under checked
//     Sendable verification.
//
// The two objects we can't fully check are:
//   1. `WCSession.default` — Apple's non-Sendable singleton. We hold no
//      instance-owned reference to it; we always access it via
//      `WCSession.default` at call sites (Apple guarantees thread safety for
//      its public API: activate/isReachable/sendMessage/updateApplicationContext
//      are all documented as safe to call from any thread).
//   2. `DelegateShim` — an `NSObject`-subclass required by the `@objc`
//      `WCSessionDelegate` protocol. NSObject subclasses cannot conform to
//      checked `Sendable`. We instead give it `@unchecked Sendable` in the
//      narrowest possible surface (a private nested type whose only role is
//      to forward callbacks to a lock-guarded handler), and we mark this
//      provider's single reference to it as `nonisolated(unsafe)` — the shim
//      instance never escapes our control after `activate()` hands it to
//      Apple. This is the checked-isolation pattern Apple documents in
//      SE-0414 (Region-based Isolation) for pre-concurrency C/ObjC APIs.

#if canImport(WatchConnectivity) && os(iOS)

public final class DefaultWatchConnectivitySessionProvider: WatchConnectivitySessionProviding {
    // `DelegateShim` is a non-Sendable NSObject subclass (required by the
    // `@objc WCSessionDelegate` protocol). We store it via
    // `nonisolated(unsafe) let` — a per-property, Swift 6-blessed narrow
    // escape hatch (SE-0412 / SE-0414) rather than class-wide
    // `@unchecked Sendable`. The shim is:
    //   * assigned once, at init time, on the initializing thread;
    //   * handed to `WCSession.default.delegate` inside `activate()`; after
    //     that Apple retains it and dispatches to it on WCSession's private
    //     serial queue;
    //   * never mutated by us after init, never read from our own
    //     concurrent code paths (we always talk to it through the shim's
    //     own lock-guarded handler slot, from within Apple's serial queue).
    // These invariants make it safe to share across concurrency domains.
    nonisolated(unsafe) private let shim: DelegateShim

    public init() {
        self.shim = DelegateShim()
    }

    // WCSession.default returns a non-Sendable singleton, but Apple
    // documents its accessors as thread-safe. We never store it as an
    // instance-owned property; each accessor calls WCSession.default
    // directly so the compiler doesn't have to reason about our sharing it.
    public var isSupported: Bool { WCSession.isSupported() }
    public var isPaired: Bool { WCSession.default.isPaired }
    public var isWatchAppInstalled: Bool { WCSession.default.isWatchAppInstalled }
    public var isReachable: Bool { WCSession.default.isReachable }

    public func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = shim
        WCSession.default.activate()
    }

    public func setDelegate(_ delegate: any WatchConnectivitySessionDelegateHandling) {
        shim.setHandler(delegate)
    }

    public func sendMessage(_ dictionary: [String: Any]) throws {
        guard WCSession.default.isReachable else {
            throw WatchConnectivityBridgeError.notReachable
        }
        WCSession.default.sendMessage(dictionary, replyHandler: nil, errorHandler: nil)
    }

    public func updateApplicationContext(_ dictionary: [String: Any]) throws {
        try WCSession.default.updateApplicationContext(dictionary)
    }
}

extension DefaultWatchConnectivitySessionProvider: Sendable {}

// MARK: - DelegateShim (private NSObject bridge)
//
// The only place `@unchecked Sendable` remains is on this private nested type.
// Rationale (documented per §Constitution II):
//   * `WCSessionDelegate` is an `@objc` protocol; conforming types MUST
//     inherit from `NSObject`. NSObject subclasses cannot express checked
//     `Sendable` conformance in Swift 6 — that's a language/ObjC-runtime
//     boundary, not our choice.
//   * The shim's ONLY mutable state is a `weak` handler reference guarded
//     by `OSAllocatedUnfairLock` (itself Sendable). Every callback path
//     reads/writes only through the lock.
//   * The shim never touches WCSession internals; it just forwards
//     Sendable-safe values (Bool, Error?) or `[String: Any]` dictionaries
//     — the latter are decoded synchronously in the target actor's
//     nonisolated shim (see `PhoneWorkoutSessionManager` above), so
//     `[String: Any]` never leaves the delegate thread.
// This is the smallest possible unchecked surface: 30 lines instead of
// spreading across the whole provider.

private final class DelegateShim: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let handlerBox = OSAllocatedUnfairLock<HandlerBox>(initialState: HandlerBox())

    private struct HandlerBox: Sendable {
        weak var handler: (any WatchConnectivitySessionDelegateHandling)?
    }

    func setHandler(_ handler: any WatchConnectivitySessionDelegateHandling) {
        handlerBox.withLock { $0.handler = handler }
    }

    private func currentHandler() -> (any WatchConnectivitySessionDelegateHandling)? {
        handlerBox.withLock { $0.handler }
    }

    func session(
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

    func sessionDidBecomeInactive(_ session: WCSession) {
        currentHandler()?.sessionDidChangeReachability(isReachable: session.isReachable)
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Per Apple guidance re-activate to allow switching watches.
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        currentHandler()?.sessionDidChangeReachability(isReachable: session.isReachable)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        currentHandler()?.sessionDidReceiveMessage(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        currentHandler()?.sessionDidReceiveApplicationContext(applicationContext)
    }
}

#endif // canImport(WatchConnectivity) && os(iOS)

public enum WatchConnectivityBridgeError: Error, Sendable, Equatable {
    case notReachable
    case notSupported
}
