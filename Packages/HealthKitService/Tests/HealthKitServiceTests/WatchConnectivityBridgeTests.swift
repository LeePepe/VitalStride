import Testing
import Foundation
@testable import HealthKitService

// MARK: - Codec tests

@Suite("WatchConnectivityCodec round-trip")
struct WatchConnectivityCodecRoundTripTests {

    @Test("LiveHeartRatePayload round-trip")
    func liveHRRoundTrip() throws {
        let payload = LiveHeartRatePayload(
            bpm: 142,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            sourceName: "Apple Watch"
        )
        let data = try WatchConnectivityCodec.encode(.liveHeartRate(payload))
        let decoded = try WatchConnectivityCodec.decode(data)
        #expect(decoded == .liveHeartRate(payload))
    }

    @Test("WorkoutStateSnapshot round-trip")
    func snapshotRoundTrip() throws {
        let snapshot = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: UUID(),
            currentExerciseName: "Bench Press",
            sets: [
                .init(id: UUID(), index: 0, targetReps: 8, targetWeightKg: 60, isCompleted: true),
                .init(id: UUID(), index: 1, targetReps: 8, targetWeightKg: 60, isCompleted: false),
            ],
            elapsedSeconds: 120,
            progress: .init(completedSetCount: 1, totalSetCount: 2),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try WatchConnectivityCodec.encode(.workoutState(snapshot))
        let decoded = try WatchConnectivityCodec.decode(data)
        #expect(decoded == .workoutState(snapshot))
    }

    @Test("WatchScreenConfig round-trip")
    func configRoundTrip() throws {
        let config = WatchScreenConfig(
            preset: .nextFocus,
            enabledModules: [.currentExercise, .nextExercise, .setProgress],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let data = try WatchConnectivityCodec.encode(.watchScreenConfig(config))
        let decoded = try WatchConnectivityCodec.decode(data)
        #expect(decoded == .watchScreenConfig(config))
    }

    @Test("SetCompletedEvent round-trip")
    func setCompletedRoundTrip() throws {
        let event = SetCompletedEvent(
            workoutID: UUID(),
            setID: UUID(),
            actualReps: 7,
            completedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
        let data = try WatchConnectivityCodec.encode(.setCompleted(event))
        let decoded = try WatchConnectivityCodec.decode(data)
        #expect(decoded == .setCompleted(event))
    }

    @Test("Dictionary transport round-trip")
    func dictionaryRoundTrip() throws {
        let payload = LiveHeartRatePayload(bpm: 88, timestamp: Date(timeIntervalSince1970: 1_700_000_400), sourceName: nil)
        let dict = try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(payload))
        let decoded = try WatchConnectivityCodec.decodeDictionary(dict)
        #expect(decoded == .liveHeartRate(payload))
    }
}

@Suite("WatchConnectivityCodec malformed inputs")
struct WatchConnectivityCodecErrorTests {

    @Test("Garbage bytes throw malformedEnvelope")
    func garbageEnvelope() {
        let data = Data([0x00, 0x01, 0x02])
        #expect(throws: WatchConnectivityCodecError.self) {
            _ = try WatchConnectivityCodec.decode(data)
        }
    }

    @Test("Unknown kind throws malformedEnvelope")
    func unknownKind() {
        let json = #"{"kind":"pizza","payload":null}"#
        let data = Data(json.utf8)
        #expect(throws: WatchConnectivityCodecError.self) {
            _ = try WatchConnectivityCodec.decode(data)
        }
    }

    @Test("Missing payload for HR throws missingPayload")
    func missingPayload() {
        let json = #"{"kind":"liveHeartRate"}"#
        let data = Data(json.utf8)
        do {
            _ = try WatchConnectivityCodec.decode(data)
            Issue.record("expected throw")
        } catch let error as WatchConnectivityCodecError {
            if case .missingPayload(let kind) = error {
                #expect(kind == "liveHeartRate")
            } else {
                Issue.record("wrong error: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("Malformed HR payload (missing bpm) throws malformedPayload")
    func malformedHR() throws {
        let malformed: [String: Any] = ["kind": "liveHeartRate"]
        // Wrap as an envelope with garbage payload bytes
        let payloadData = Data(#"{"notBpm":1}"#.utf8)
        var envelopeDict = malformed
        envelopeDict["payload"] = payloadData.base64EncodedString()
        // Manually construct the envelope JSON
        let json = #"{"kind":"liveHeartRate","payload":"\#(payloadData.base64EncodedString())"}"#
        let data = Data(json.utf8)
        do {
            _ = try WatchConnectivityCodec.decode(data)
            Issue.record("expected throw")
        } catch let error as WatchConnectivityCodecError {
            if case .malformedPayload(let kind) = error {
                #expect(kind == "liveHeartRate")
            } else {
                Issue.record("wrong error: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("Dictionary without envelope key throws malformedEnvelope")
    func missingEnvelopeKey() {
        let dict: [String: Any] = ["not_envelope": Data()]
        #expect(throws: WatchConnectivityCodecError.self) {
            _ = try WatchConnectivityCodec.decodeDictionary(dict)
        }
    }
}

@Suite("LiveHeartRatePayload physiological gate")
struct LiveHeartRateGateTests {

    @Test("Zero is rejected")
    func zeroRejected() {
        let p = LiveHeartRatePayload(bpm: 0, timestamp: Date(), sourceName: nil)
        #expect(!p.isPhysiologicallyPlausible)
    }

    @Test("Negative is rejected")
    func negativeRejected() {
        let p = LiveHeartRatePayload(bpm: -10, timestamp: Date(), sourceName: nil)
        #expect(!p.isPhysiologicallyPlausible)
    }

    @Test("301 is rejected")
    func over300Rejected() {
        let p = LiveHeartRatePayload(bpm: 301, timestamp: Date(), sourceName: nil)
        #expect(!p.isPhysiologicallyPlausible)
    }

    @Test("Normal 72 is accepted")
    func normalAccepted() {
        let p = LiveHeartRatePayload(bpm: 72, timestamp: Date(), sourceName: nil)
        #expect(p.isPhysiologicallyPlausible)
    }
}

// MARK: - Fake session

final class FakeWCSession: WatchConnectivitySessionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _isSupported = true
    private var _isPaired = true
    private var _isWatchAppInstalled = true
    private var _isReachable = false
    private weak var handler: (any WatchConnectivitySessionDelegateHandling)?
    private(set) var sentApplicationContexts: [[String: Any]] = []
    private(set) var sentMessages: [[String: Any]] = []
    private(set) var activateCallCount = 0

    var isSupported: Bool { lock.withLock { _isSupported } }
    var isPaired: Bool { lock.withLock { _isPaired } }
    var isWatchAppInstalled: Bool { lock.withLock { _isWatchAppInstalled } }
    var isReachable: Bool { lock.withLock { _isReachable } }

    func set(isSupported: Bool? = nil, isPaired: Bool? = nil, isWatchAppInstalled: Bool? = nil, isReachable: Bool? = nil) {
        lock.withLock {
            if let v = isSupported { _isSupported = v }
            if let v = isPaired { _isPaired = v }
            if let v = isWatchAppInstalled { _isWatchAppInstalled = v }
            if let v = isReachable { _isReachable = v }
        }
    }

    func activate() {
        lock.withLock { activateCallCount += 1 }
        let handler = lock.withLock { self.handler }
        handler?.sessionDidActivate(
            isSupported: isSupported,
            isPaired: isPaired,
            isWatchAppInstalled: isWatchAppInstalled,
            isReachable: isReachable,
            error: nil
        )
    }

    func setDelegate(_ delegate: any WatchConnectivitySessionDelegateHandling) {
        lock.withLock { handler = delegate }
    }

    func sendMessage(_ dictionary: [String: Any]) throws {
        guard isReachable else { throw WatchConnectivityBridgeError.notReachable }
        lock.withLock { sentMessages.append(dictionary) }
    }

    func updateApplicationContext(_ dictionary: [String: Any]) throws {
        lock.withLock { sentApplicationContexts.append(dictionary) }
    }

    // Test-only push helpers
    func simulateIncomingMessage(_ dictionary: [String: Any]) {
        let handler = lock.withLock { self.handler }
        handler?.sessionDidReceiveMessage(dictionary)
    }

    func simulateReachabilityChange(_ reachable: Bool) {
        set(isReachable: reachable)
        let handler = lock.withLock { self.handler }
        handler?.sessionDidChangeReachability(isReachable: reachable)
    }
}

// MARK: - PhoneWorkoutSessionManager tests

@Suite("PhoneWorkoutSessionManager connection state")
struct PhoneConnectionStateTests {

    @Test("Unsupported session emits .unsupported")
    func unsupportedState() async {
        let fake = FakeWCSession()
        fake.set(isSupported: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        var iterator = manager.observeConnectionState().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .unsupported)
    }

    @Test("Not paired emits .notPaired")
    func notPairedState() async {
        let fake = FakeWCSession()
        fake.set(isPaired: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        var iterator = manager.observeConnectionState().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .notPaired)
    }

    @Test("Watch app not installed emits .notInstalled")
    func notInstalledState() async {
        let fake = FakeWCSession()
        fake.set(isWatchAppInstalled: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        var iterator = manager.observeConnectionState().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .notInstalled)
    }

    @Test("Unreachable emits .unreachable")
    func unreachableState() async {
        let fake = FakeWCSession()
        fake.set(isReachable: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        var iterator = manager.observeConnectionState().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .unreachable)
    }

    @Test("Reachable emits .reachable and reachability change is streamed")
    func reachabilityTransition() async {
        let fake = FakeWCSession()
        fake.set(isReachable: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        let stream = manager.observeConnectionState()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .unreachable)

        fake.simulateReachabilityChange(true)
        let next = await iterator.next()
        #expect(next == .reachable)
    }
}

@Suite("PhoneWorkoutSessionManager HR forwarding")
struct PhoneHRForwardingTests {

    @Test("HR is dropped when session inactive")
    func hrDroppedWhenInactive() async throws {
        let fake = FakeWCSession()
        fake.set(isReachable: true)
        let manager = PhoneWorkoutSessionManager(session: fake)

        let stream = manager.observeLiveWorkoutHeartRate()

        // Push HR while no session active.
        let ts = Date(timeIntervalSince1970: 1_700_000_900)
        let payload = LiveHeartRatePayload(bpm: 88, timestamp: ts, sourceName: nil)
        let dict = try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(payload))
        fake.simulateIncomingMessage(dict)

        // Now start a session and push again — this one should arrive.
        await manager.startSession()
        let payload2 = LiveHeartRatePayload(bpm: 100, timestamp: ts, sourceName: nil)
        let dict2 = try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(payload2))
        fake.simulateIncomingMessage(dict2)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == payload2)
    }

    @Test("Out-of-range HR is silently dropped")
    func hrOutOfRangeDropped() async throws {
        let fake = FakeWCSession()
        fake.set(isReachable: true)
        let manager = PhoneWorkoutSessionManager(session: fake)
        await manager.startSession()

        let stream = manager.observeLiveWorkoutHeartRate()

        let ts = Date(timeIntervalSince1970: 1_700_000_500)
        let bad = LiveHeartRatePayload(bpm: 900, timestamp: ts, sourceName: nil)
        fake.simulateIncomingMessage(try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(bad)))

        let good = LiveHeartRatePayload(bpm: 72, timestamp: ts, sourceName: nil)
        fake.simulateIncomingMessage(try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(good)))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == good)
    }

    @Test("Malformed payload does not crash")
    func malformedPayloadNoCrash() async {
        let fake = FakeWCSession()
        fake.set(isReachable: true)
        let manager = PhoneWorkoutSessionManager(session: fake)
        await manager.startSession()

        fake.simulateIncomingMessage(["garbage": "here"])
        fake.simulateIncomingMessage(["envelope": Data("nonsense".utf8)])
        // Reaching this line without a crash is the assertion.
        #expect(Bool(true))
    }
}

@Suite("PhoneWorkoutSessionManager SetCompleted stream")
struct PhoneSetCompletedTests {

    @Test("SetCompletedEvent is forwarded to observers")
    func setCompletedForwarded() async throws {
        let fake = FakeWCSession()
        let manager = PhoneWorkoutSessionManager(session: fake)
        let stream = manager.observeSetCompleted()

        let event = SetCompletedEvent(
            workoutID: UUID(),
            setID: UUID(),
            actualReps: 8,
            completedAt: Date(timeIntervalSince1970: 1_700_000_600)
        )
        let dict = try WatchConnectivityCodec.encodeDictionary(.setCompleted(event))
        fake.simulateIncomingMessage(dict)

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == event)
    }
}

@Suite("PhoneWorkoutSessionManager outgoing state")
struct PhoneOutgoingStateTests {

    @Test("updateWorkoutState pushes to application context")
    func updateWorkoutStatePushes() async throws {
        let fake = FakeWCSession()
        let manager = PhoneWorkoutSessionManager(session: fake)

        let snapshot = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: nil,
            currentExerciseName: "Squat",
            sets: [],
            elapsedSeconds: 30,
            progress: .init(completedSetCount: 0, totalSetCount: 5),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_700)
        )
        await manager.updateWorkoutState(snapshot)

        #expect(fake.sentApplicationContexts.count == 1)
        let decoded = try WatchConnectivityCodec.decodeDictionary(fake.sentApplicationContexts[0])
        #expect(decoded == .workoutState(snapshot))
    }

    @Test("updateWatchScreenConfig pushes to application context")
    func updateScreenConfigPushes() async throws {
        let fake = FakeWCSession()
        let manager = PhoneWorkoutSessionManager(session: fake)

        let config = WatchScreenConfig(
            preset: .hrFocus,
            enabledModules: [.heartRate, .timer],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_800)
        )
        await manager.updateWatchScreenConfig(config)

        #expect(fake.sentApplicationContexts.count == 1)
        let decoded = try WatchConnectivityCodec.decodeDictionary(fake.sentApplicationContexts[0])
        #expect(decoded == .watchScreenConfig(config))
    }
}

// MARK: - Contract: WatchScreenConfig carries no HK values (privacy §I)

@Suite("WatchScreenConfig privacy contract")
struct WatchScreenConfigPrivacyTests {

    @Test("WatchScreenConfig public surface has no HK-value-shaped fields")
    func configHasNoHealthValues() throws {
        // Serialize a maximally-populated config and inspect the JSON keys.
        // If a future edit adds `bpm`/`weight`/`reps`/`stepCount` etc. to this
        // type, this test flags it.
        let config = WatchScreenConfig(
            preset: .fullInfo,
            enabledModules: Set(WatchScreenConfig.Module.allCases),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let data = try JSONEncoder().encode(config)
        let json = String(data: data, encoding: .utf8) ?? ""

        // These substrings would indicate an accidental leak.
        let forbidden = ["bpm", "\"weight", "\"reps", "stepCount", "heartRate\":"]
        for token in forbidden {
            // `heartRate` appears as an enum case name (module identifier). The
            // check above uses `heartRate\":` (dict value form) which shouldn't
            // appear because it's a set element, not a key.
            #expect(!json.contains(token), "WatchScreenConfig JSON leaked token \(token): \(json)")
        }
    }
}
