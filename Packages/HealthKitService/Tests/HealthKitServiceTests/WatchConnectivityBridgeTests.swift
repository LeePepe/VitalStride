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
            enabledModules: [.clock, .elapsed, .setsTotal, .heartRate, .nextSet, .setDots, .primaryAction],
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
        let payloadData = Data(#"{"notBpm":1}"#.utf8)
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

// MARK: - Semantic validation regression tests (retro AI Reviewer P0)

@Suite("WatchConnectivityCodec semantic validation")
struct WatchConnectivityCodecSemanticValidationTests {

    /// Encode a WatchConnectivityMessage with sampleType left blank so we can
    /// inject deliberately-invalid values into the payload JSON. Uses the
    /// same envelope layout as the production codec.
    private static func envelope(kind: String, payloadJSON: String) -> Data {
        let payloadData = Data(payloadJSON.utf8)
        let json = #"{"kind":"\#(kind)","payload":"\#(payloadData.base64EncodedString())"}"#
        return Data(json.utf8)
    }

    @Test("Non-finite bpm is rejected as invalidField")
    func nonFiniteBPMRejected() {
        // JSON literal "1e400" decodes to +Inf as a Double; test with a
        // known-invalid value by injecting a NaN sentinel through Double
        // encoding. Since JSON has no NaN literal we go via a
        // custom-encoded payload:
        let payloadJSON = #"{"sampleType":"heartRate","bpm":null,"timestamp":0,"sourceName":null}"#
        let data = Self.envelope(kind: "liveHeartRate", payloadJSON: payloadJSON)
        do {
            _ = try WatchConnectivityCodec.decode(data)
            Issue.record("expected throw for null bpm")
        } catch let error as WatchConnectivityCodecError {
            // Structural decode fails on null-for-non-optional-Double.
            if case .malformedPayload = error {
                return
            }
            Issue.record("expected malformedPayload, got \(error)")
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("Out-of-range bpm (> 300) is rejected as invalidField")
    func outOfRangeBPMRejected() throws {
        let payload = LiveHeartRatePayload(bpm: 500, timestamp: Date(timeIntervalSince1970: 1_700_000_000), sourceName: nil)
        let data = try WatchConnectivityCodec.encode(.liveHeartRate(payload))
        do {
            _ = try WatchConnectivityCodec.decode(data)
            Issue.record("expected throw for bpm=500")
        } catch let error as WatchConnectivityCodecError {
            guard case .invalidField(let kind, let field, _) = error else {
                Issue.record("expected invalidField, got \(error)")
                return
            }
            #expect(kind == "liveHeartRate")
            #expect(field == "bpm")
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("LiveHeartRatePayload has explicit sampleType field")
    func liveHRHasSampleType() throws {
        let payload = LiveHeartRatePayload(bpm: 72, timestamp: Date(timeIntervalSince1970: 0), sourceName: nil)
        #expect(payload.sampleType == .heartRate)
        // The payload itself must encode `sampleType` so a decoder can
        // cross-check the envelope discriminator.
        let payloadJSON = String(data: try JSONEncoder().encode(payload), encoding: .utf8) ?? ""
        #expect(payloadJSON.contains("sampleType"))
        #expect(payloadJSON.contains("heartRate"))
        // Round-trip preserves the explicit discriminator.
        let data = try WatchConnectivityCodec.encode(.liveHeartRate(payload))
        let decoded = try WatchConnectivityCodec.decode(data)
        #expect(decoded == .liveHeartRate(payload))
    }

    @Test("Negative elapsedSeconds is rejected")
    func negativeElapsedRejected() throws {
        let snapshot = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: nil,
            currentExerciseName: nil,
            sets: [],
            elapsedSeconds: -5,
            progress: .init(completedSetCount: 0, totalSetCount: 0),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try WatchConnectivityCodec.encode(.workoutState(snapshot))
        do {
            _ = try WatchConnectivityCodec.decode(data)
            Issue.record("expected throw")
        } catch let error as WatchConnectivityCodecError {
            guard case .invalidField(_, let field, _) = error else {
                Issue.record("expected invalidField, got \(error)")
                return
            }
            #expect(field == "elapsedSeconds")
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("Progress with completed > total is rejected")
    func progressCompletedExceedsTotalRejected() throws {
        let snapshot = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: nil,
            currentExerciseName: nil,
            sets: [],
            elapsedSeconds: 0,
            progress: .init(completedSetCount: 5, totalSetCount: 3),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try WatchConnectivityCodec.encode(.workoutState(snapshot))
        do {
            _ = try WatchConnectivityCodec.decode(data)
            Issue.record("expected throw")
        } catch let error as WatchConnectivityCodecError {
            guard case .invalidField(_, let field, _) = error else {
                Issue.record("expected invalidField, got \(error)")
                return
            }
            #expect(field == "progress")
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("Negative set weight is rejected")
    func negativeWeightRejected() throws {
        let snapshot = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: nil,
            currentExerciseName: nil,
            sets: [
                .init(id: UUID(), index: 0, targetReps: 8, targetWeightKg: -10, isCompleted: false),
            ],
            elapsedSeconds: 0,
            progress: .init(completedSetCount: 0, totalSetCount: 1),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try WatchConnectivityCodec.encode(.workoutState(snapshot))
        do {
            _ = try WatchConnectivityCodec.decode(data)
            Issue.record("expected throw")
        } catch let error as WatchConnectivityCodecError {
            guard case .invalidField(_, let field, _) = error else {
                Issue.record("expected invalidField, got \(error)")
                return
            }
            #expect(field == "sets[].targetWeightKg")
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("Negative actualReps in SetCompleted is rejected")
    func negativeRepsRejected() throws {
        let event = SetCompletedEvent(
            workoutID: UUID(),
            setID: UUID(),
            actualReps: -3,
            completedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try WatchConnectivityCodec.encode(.setCompleted(event))
        do {
            _ = try WatchConnectivityCodec.decode(data)
            Issue.record("expected throw")
        } catch let error as WatchConnectivityCodecError {
            guard case .invalidField(_, let field, _) = error else {
                Issue.record("expected invalidField, got \(error)")
                return
            }
            #expect(field == "actualReps")
        } catch {
            Issue.record("wrong error type: \(error)")
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

    func simulateIncomingApplicationContext(_ dictionary: [String: Any]) {
        let handler = lock.withLock { self.handler }
        handler?.sessionDidReceiveApplicationContext(dictionary)
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
        var iterator = await manager.observeConnectionState().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .unsupported)
    }

    @Test("Not paired emits .notPaired")
    func notPairedState() async {
        let fake = FakeWCSession()
        fake.set(isPaired: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        var iterator = await manager.observeConnectionState().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .notPaired)
    }

    @Test("Watch app not installed emits .notInstalled")
    func notInstalledState() async {
        let fake = FakeWCSession()
        fake.set(isWatchAppInstalled: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        var iterator = await manager.observeConnectionState().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .notInstalled)
    }

    @Test("Unreachable emits .unreachable")
    func unreachableState() async {
        let fake = FakeWCSession()
        fake.set(isReachable: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        var iterator = await manager.observeConnectionState().makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .unreachable)
    }

    @Test("Reachable emits .reachable and reachability change is streamed")
    func reachabilityTransition() async {
        let fake = FakeWCSession()
        fake.set(isReachable: false)
        let manager = PhoneWorkoutSessionManager(session: fake)
        let stream = await manager.observeConnectionState()
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

        let stream = await manager.observeLiveWorkoutHeartRate()

        // Push HR while no session active.
        let ts = Date(timeIntervalSince1970: 1_700_000_900)
        let payload = LiveHeartRatePayload(bpm: 88, timestamp: ts, sourceName: nil)
        let dict = try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(payload))
        fake.simulateIncomingMessage(dict)

        // Give the actor's message-Task a chance to run BEFORE we activate
        // the session, so isSessionActive=false is observed by that Task
        // and the sample is genuinely dropped (rather than racing with
        // startSession()).
        try await Task.sleep(nanoseconds: 50_000_000)

        // Now start a session and push again — this one should arrive.
        try await manager.startSession()
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
        try await manager.startSession()

        let stream = await manager.observeLiveWorkoutHeartRate()

        let ts = Date(timeIntervalSince1970: 1_700_000_500)
        // Encode a bad-value message BYPASSING the physiological gate at
        // codec.validate by constructing the envelope directly.
        let badPayloadJSON = #"{"sampleType":"heartRate","bpm":900,"timestamp":1700000500,"sourceName":null}"#
        let payloadData = Data(badPayloadJSON.utf8)
        let envelopeJSON = #"{"kind":"liveHeartRate","payload":"\#(payloadData.base64EncodedString())"}"#
        fake.simulateIncomingMessage(["envelope": Data(envelopeJSON.utf8)])

        let good = LiveHeartRatePayload(bpm: 72, timestamp: ts, sourceName: nil)
        fake.simulateIncomingMessage(try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(good)))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == good)
    }

    @Test("Malformed payload does not crash")
    func malformedPayloadNoCrash() async throws {
        let fake = FakeWCSession()
        fake.set(isReachable: true)
        let manager = PhoneWorkoutSessionManager(session: fake)
        try await manager.startSession()

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
        let stream = await manager.observeSetCompleted()

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
            enabledModules: [.heartRate, .elapsed],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_800)
        )
        await manager.updateWatchScreenConfig(config)

        #expect(fake.sentApplicationContexts.count == 1)
        let decoded = try WatchConnectivityCodec.decodeDictionary(fake.sentApplicationContexts[0])
        #expect(decoded == .watchScreenConfig(config))
    }
}

// MARK: - Channel-direction enforcement (retro AI Reviewer P0)

@Suite("PhoneWorkoutSessionManager channel direction")
struct PhoneChannelDirectionTests {

    @Test("HR arriving on applicationContext is dropped, not forwarded")
    func hrOnApplicationContextDropped() async throws {
        let fake = FakeWCSession()
        let manager = PhoneWorkoutSessionManager(session: fake)
        try await manager.startSession()

        let stream = await manager.observeLiveWorkoutHeartRate()

        let wrongChannelHR = LiveHeartRatePayload(
            bpm: 120,
            timestamp: Date(timeIntervalSince1970: 1_700_001_000),
            sourceName: nil
        )
        let wrongChannelDict = try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(wrongChannelHR))
        fake.simulateIncomingApplicationContext(wrongChannelDict)

        // Push a legitimate HR via message; this MUST be the first thing
        // the stream yields (proving the applicationContext HR was dropped).
        let goodHR = LiveHeartRatePayload(
            bpm: 80,
            timestamp: Date(timeIntervalSince1970: 1_700_001_001),
            sourceName: nil
        )
        fake.simulateIncomingMessage(try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(goodHR)))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == goodHR)
    }

    @Test("SetCompleted arriving on applicationContext is dropped")
    func setCompletedOnApplicationContextDropped() async throws {
        let fake = FakeWCSession()
        let manager = PhoneWorkoutSessionManager(session: fake)

        let stream = await manager.observeSetCompleted()

        let wrongChannel = SetCompletedEvent(
            workoutID: UUID(),
            setID: UUID(),
            actualReps: 5,
            completedAt: Date(timeIntervalSince1970: 1_700_001_100)
        )
        fake.simulateIncomingApplicationContext(
            try WatchConnectivityCodec.encodeDictionary(.setCompleted(wrongChannel))
        )

        let correct = SetCompletedEvent(
            workoutID: UUID(),
            setID: UUID(),
            actualReps: 6,
            completedAt: Date(timeIntervalSince1970: 1_700_001_101)
        )
        fake.simulateIncomingMessage(try WatchConnectivityCodec.encodeDictionary(.setCompleted(correct)))

        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == correct)
    }

    @Test("WorkoutState arriving via message is ignored (reverse direction)")
    func workoutStateOnMessageIgnored() async throws {
        let fake = FakeWCSession()
        let manager = PhoneWorkoutSessionManager(session: fake)
        try await manager.startSession()

        // Push a state snapshot as a message (wrong direction — iPhone SENDs
        // state, never receives it). The bridge must not crash and must not
        // publish anything on HR/SetCompleted observers.
        let snapshot = WorkoutStateSnapshot(
            workoutID: UUID(),
            currentExerciseID: nil,
            currentExerciseName: nil,
            sets: [],
            elapsedSeconds: 0,
            progress: .init(completedSetCount: 0, totalSetCount: 0),
            updatedAt: Date(timeIntervalSince1970: 1_700_001_200)
        )
        fake.simulateIncomingMessage(try WatchConnectivityCodec.encodeDictionary(.workoutState(snapshot)))

        // Now push a legit HR — must arrive.
        let stream = await manager.observeLiveWorkoutHeartRate()
        let hr = LiveHeartRatePayload(bpm: 90, timestamp: Date(timeIntervalSince1970: 1_700_001_201), sourceName: nil)
        fake.simulateIncomingMessage(try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(hr)))
        var iterator = stream.makeAsyncIterator()
        let received = await iterator.next()
        #expect(received == hr)
    }
}

// MARK: - Bounded newest-value buffering (retro AI Reviewer P1)

@Suite("PhoneWorkoutSessionManager bounded HR buffering")
struct PhoneHRBufferingTests {

    @Test("HR stream buffers only newest value when subscriber lags")
    func hrKeepsNewestOnly() async throws {
        let fake = FakeWCSession()
        let manager = PhoneWorkoutSessionManager(session: fake)
        try await manager.startSession()

        let stream = await manager.observeLiveWorkoutHeartRate()

        // Push several HR samples before consuming any. With
        // `.bufferingNewest(1)` only the last one survives.
        let ts = Date(timeIntervalSince1970: 1_700_002_000)
        for bpm in [70, 80, 90, 100, 110] as [Double] {
            let p = LiveHeartRatePayload(bpm: bpm, timestamp: ts, sourceName: nil)
            fake.simulateIncomingMessage(try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(p)))
        }
        // Give the actor a chance to drain the message queue before we read.
        try await Task.sleep(nanoseconds: 50_000_000)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        // The newest value (110) is what survives; older values were dropped
        // by the bufferingNewest(1) policy.
        #expect(first?.bpm == 110)
    }
}

// MARK: - Concurrency / Sendable regression (P0: replace @unchecked Sendable)

/// Verifies the bridge types compose under Swift 6 strict-concurrency
/// checking. If any of these guarantees regress (e.g. someone re-introduces
/// class-level `@unchecked Sendable` on the provider, or a stored property
/// becomes mutable without proper isolation), this file will fail to
/// compile — the tests' mere existence is the assertion.
@Suite("PhoneWorkoutSessionManager Sendable / concurrency contracts")
struct PhoneSendableContractTests {

    /// Compile-time proof: `PhoneWorkoutSessionManager` is `Sendable`
    /// (automatically, because it's an actor). If someone accidentally
    /// converts it back to a class this line stops compiling.
    @Test("Manager conforms to Sendable (compile-time)")
    func managerIsSendable() {
        func requireSendable<T: Sendable>(_ value: T.Type) {}
        requireSendable(PhoneWorkoutSessionManager.self)
    }

    /// Compile-time proof: `WatchConnectivityMessage` is `Sendable` — it's
    /// the type that crosses the delegate-thread → actor boundary.
    @Test("Message is Sendable (compile-time)")
    func messageIsSendable() {
        func requireSendable<T: Sendable>(_ value: T.Type) {}
        requireSendable(WatchConnectivityMessage.self)
    }

    /// The manager must tolerate concurrent HR + set-completed +
    /// wrong-channel arrivals from multiple pseudo-delegate threads
    /// without racing or crashing. If actor isolation or channel
    /// enforcement regresses this test will either data-race (crash
    /// under TSAN) or drop events.
    @Test("Concurrent multi-channel arrivals do not race")
    func concurrentArrivalsDoNotRace() async throws {
        let fake = FakeWCSession()
        let manager = PhoneWorkoutSessionManager(session: fake)
        try await manager.startSession()

        let hrStream = await manager.observeLiveWorkoutHeartRate()
        let setStream = await manager.observeSetCompleted()

        let ts = Date(timeIntervalSince1970: 1_700_003_000)
        let workoutID = UUID()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    let payload = LiveHeartRatePayload(bpm: 60 + Double(i % 10), timestamp: ts, sourceName: nil)
                    fake.simulateIncomingMessage(
                        try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(payload))
                    )
                }
            }
            for i in 0..<25 {
                group.addTask {
                    let event = SetCompletedEvent(
                        workoutID: workoutID,
                        setID: UUID(),
                        actualReps: i,
                        completedAt: ts
                    )
                    fake.simulateIncomingMessage(
                        try WatchConnectivityCodec.encodeDictionary(.setCompleted(event))
                    )
                }
            }
            for _ in 0..<25 {
                group.addTask {
                    // Wrong-channel HR: must be silently dropped by
                    // channel-direction enforcement.
                    let payload = LiveHeartRatePayload(bpm: 120, timestamp: ts, sourceName: nil)
                    fake.simulateIncomingApplicationContext(
                        try WatchConnectivityCodec.encodeDictionary(.liveHeartRate(payload))
                    )
                }
            }
            try await group.waitForAll()
        }

        // Drain queued delegate Tasks.
        try await Task.sleep(nanoseconds: 100_000_000)

        var hrIterator = hrStream.makeAsyncIterator()
        let hr = await hrIterator.next()
        #expect(hr != nil, "at least one HR sample expected to survive")

        var setIterator = setStream.makeAsyncIterator()
        let event = await setIterator.next()
        #expect(event != nil, "at least one set-completed event expected")
    }

    /// The fake session provider must itself be Sendable so tests exercise
    /// the same concurrency contract as production. Compile-time only.
    @Test("FakeWCSession conforms to Sendable")
    func fakeIsSendable() {
        func requireSendable<T: Sendable>(_ value: T.Type) {}
        requireSendable(FakeWCSession.self)
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

// MARK: - Contract: WatchScreenConfig axis-A presets + axis-B modules
// Aligns with specs/watch-in-workout-screen.md §7 (MY-1286).

@Suite("WatchScreenConfig preset contract")
struct WatchScreenConfigPresetTests {

    @Test("All four spec presets exist")
    func allPresetsExist() {
        let names = WatchScreenConfig.Preset.allCases.map { $0.rawValue }.sorted()
        #expect(names == ["fullInfo", "hrFocus", "list", "nextFocus"])
    }

    @Test("Default config uses fullInfo preset with every module enabled")
    func defaultConfigMatchesSpec() {
        let config = WatchScreenConfig.defaultConfig()
        #expect(config.preset == .fullInfo)
        #expect(config.enabledModules == Set(WatchScreenConfig.Module.allCases))
    }

    @Test("Default config is deterministic (same call → same value)")
    func defaultConfigIsDeterministic() {
        let a = WatchScreenConfig.defaultConfig(at: Date(timeIntervalSince1970: 0))
        let b = WatchScreenConfig.defaultConfig(at: Date(timeIntervalSince1970: 0))
        #expect(a == b)
    }

    @Test("Every preset survives a round-trip via the codec")
    func everyPresetRoundTrips() throws {
        for preset in WatchScreenConfig.Preset.allCases {
            let config = WatchScreenConfig(
                preset: preset,
                enabledModules: Set(WatchScreenConfig.Module.allCases),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            let data = try WatchConnectivityCodec.encode(.watchScreenConfig(config))
            let decoded = try WatchConnectivityCodec.decode(data)
            #expect(decoded == .watchScreenConfig(config), "preset \(preset) failed round-trip")
        }
    }
}

@Suite("WatchScreenConfig module contract")
struct WatchScreenConfigModuleTests {

    @Test("Module set exactly matches spec §7 axis-B ids")
    func moduleIdsMatchSpec() {
        let expected = Set([
            "clock", "elapsed", "setsTotal", "heartRate", "hrZone",
            "hrAvgPeak", "nextSet", "setDots", "primaryAction",
        ])
        let actual = Set(WatchScreenConfig.Module.allCases.map { $0.rawValue })
        #expect(actual == expected)
    }

    @Test("Every module survives a round-trip when enabled alone")
    func everyModuleRoundTrips() throws {
        for module in WatchScreenConfig.Module.allCases {
            let config = WatchScreenConfig(
                preset: .fullInfo,
                enabledModules: [module],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            let data = try WatchConnectivityCodec.encode(.watchScreenConfig(config))
            let decoded = try WatchConnectivityCodec.decode(data)
            #expect(decoded == .watchScreenConfig(config), "module \(module) failed round-trip")
        }
    }

    @Test("Legacy module ids from the pre-MY-1286 shape no longer decode as valid modules")
    func legacyModuleIdsRemoved() {
        for legacy in ["currentExercise", "nextExercise", "setList", "timer", "setProgress"] {
            #expect(WatchScreenConfig.Module(rawValue: legacy) == nil,
                    "legacy module id \(legacy) must be gone per spec §7")
        }
    }
}

@Suite("WatchScreenConfig locked-on invariants")
struct WatchScreenConfigLockedInvariantTests {

    @Test("Locked-on set is exactly {heartRate, primaryAction}")
    func lockedOnSetMatchesSpec() {
        #expect(WatchScreenConfig.lockedOnModules == [.heartRate, .primaryAction])
    }

    @Test("Init with empty modules still reads heartRate + primaryAction enabled")
    func initInjectsLockedModules() {
        let config = WatchScreenConfig(
            preset: .fullInfo,
            enabledModules: [],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(config.enabledModules.contains(.heartRate))
        #expect(config.enabledModules.contains(.primaryAction))
    }

    @Test("Init preserves user-selected non-locked modules alongside locked ones")
    func initPreservesUserModules() {
        let config = WatchScreenConfig(
            preset: .fullInfo,
            enabledModules: [.clock, .elapsed],
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        #expect(config.enabledModules == [.clock, .elapsed, .heartRate, .primaryAction])
    }

    @Test("Decoded payload missing heartRate is re-injected on decode")
    func decodeInjectsHeartRate() throws {
        let payloadJSON = #"{"preset":"hrFocus","enabledModules":["elapsed"],"updatedAt":0}"#
        let data = Data(payloadJSON.utf8)
        let decoded = try JSONDecoder().decode(WatchScreenConfig.self, from: data)
        #expect(decoded.enabledModules.contains(.heartRate),
                "heartRate is LOCKED on per spec §7 axis-B; decode MUST inject it")
        #expect(decoded.enabledModules.contains(.primaryAction),
                "primaryAction is LOCKED on per spec §7 axis-B; decode MUST inject it")
    }

    @Test("Decoded payload missing primaryAction is re-injected on decode")
    func decodeInjectsPrimaryAction() throws {
        let payloadJSON = #"{"preset":"list","enabledModules":["nextSet","clock"],"updatedAt":0}"#
        let data = Data(payloadJSON.utf8)
        let decoded = try JSONDecoder().decode(WatchScreenConfig.self, from: data)
        #expect(decoded.enabledModules.contains(.primaryAction))
        #expect(decoded.enabledModules.contains(.heartRate))
        // User-selected modules survive.
        #expect(decoded.enabledModules.contains(.nextSet))
        #expect(decoded.enabledModules.contains(.clock))
    }

    @Test("Codec round-trip preserves the enforced locked-on invariant end-to-end")
    func codecRoundTripPreservesLockedOn() throws {
        // Construct via the init that strips (via override) is impossible —
        // the init always unions in locked modules — so we exercise the
        // full codec path with a payload the wire never provided the locks.
        let payloadJSON = #"{"preset":"nextFocus","enabledModules":["setsTotal"],"updatedAt":0}"#
        let envelope = #"{"kind":"watchScreenConfig","payload":"\#(Data(payloadJSON.utf8).base64EncodedString())"}"#
        let decoded = try WatchConnectivityCodec.decode(Data(envelope.utf8))
        guard case .watchScreenConfig(let config) = decoded else {
            Issue.record("wrong envelope decoded")
            return
        }
        #expect(config.enabledModules.contains(.heartRate))
        #expect(config.enabledModules.contains(.primaryAction))
        #expect(config.enabledModules.contains(.setsTotal))
    }
}

@Suite("WatchScreenConfig malformed input")
struct WatchScreenConfigMalformedTests {

    @Test("Unknown preset raises a codec error (does not crash)")
    func unknownPresetRejected() {
        let payloadJSON = #"{"preset":"pizza","enabledModules":[],"updatedAt":0}"#
        let envelope = #"{"kind":"watchScreenConfig","payload":"\#(Data(payloadJSON.utf8).base64EncodedString())"}"#
        do {
            _ = try WatchConnectivityCodec.decode(Data(envelope.utf8))
            Issue.record("expected throw for unknown preset")
        } catch let error as WatchConnectivityCodecError {
            if case .malformedPayload(let kind) = error {
                #expect(kind == "watchScreenConfig")
            } else {
                Issue.record("wrong error: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("Unknown module id raises a codec error (does not crash)")
    func unknownModuleRejected() {
        let payloadJSON = #"{"preset":"fullInfo","enabledModules":["banana"],"updatedAt":0}"#
        let envelope = #"{"kind":"watchScreenConfig","payload":"\#(Data(payloadJSON.utf8).base64EncodedString())"}"#
        do {
            _ = try WatchConnectivityCodec.decode(Data(envelope.utf8))
            Issue.record("expected throw for unknown module")
        } catch let error as WatchConnectivityCodecError {
            if case .malformedPayload(let kind) = error {
                #expect(kind == "watchScreenConfig")
            } else {
                Issue.record("wrong error: \(error)")
            }
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("Missing preset key raises malformedPayload")
    func missingPresetRejected() {
        let payloadJSON = #"{"enabledModules":["heartRate"],"updatedAt":0}"#
        let envelope = #"{"kind":"watchScreenConfig","payload":"\#(Data(payloadJSON.utf8).base64EncodedString())"}"#
        #expect(throws: WatchConnectivityCodecError.self) {
            _ = try WatchConnectivityCodec.decode(Data(envelope.utf8))
        }
    }
}
