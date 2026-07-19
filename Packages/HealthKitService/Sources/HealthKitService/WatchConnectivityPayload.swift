import Foundation

// MARK: - Watch ↔ iPhone Payloads (ADR-0010 Addendum 2026-07-19)
//
// Contract owned by HealthKitService layer. Watch app (T002) + iOS UI (T003/T004)
// depend on this shape. All payloads are Codable via JSON so they survive
// WCSession `sendMessage` / `updateApplicationContext` transport.
//
// Privacy §I:
//   - HR values in `LiveHeartRatePayload` are display-only, must never be logged.
//   - `WorkoutStateSnapshot` carries training data (reps/weight) which is allowed
//     to sync via CloudKit at the persistence layer, but WC transport itself is
//     ephemeral — the payload is not a new persistence surface.
//   - `WatchScreenConfig` carries no HK health values.

// MARK: Envelope

/// Discriminator so the receive path can decode any payload from one stream.
public enum WatchConnectivityMessage: Sendable, Equatable {
    case liveHeartRate(LiveHeartRatePayload)
    case workoutState(WorkoutStateSnapshot)
    case watchScreenConfig(WatchScreenConfig)
    case setCompleted(SetCompletedEvent)
}

/// JSON codec for `WatchConnectivityMessage`.
///
/// Wire shape:
/// `{ "kind": "liveHeartRate" | "workoutState" | "watchScreenConfig" | "setCompleted",
///    "payload": <payload> }`
///
/// Unknown `kind` and missing/malformed `payload` throw `WatchConnectivityCodecError`
/// (do NOT crash the delegate callback).
public enum WatchConnectivityCodec {
    public static func encode(_ message: WatchConnectivityMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let envelope: Envelope
        switch message {
        case .liveHeartRate(let p):
            envelope = try Envelope(kind: .liveHeartRate, payloadValue: p, encoder: encoder)
        case .workoutState(let p):
            envelope = try Envelope(kind: .workoutState, payloadValue: p, encoder: encoder)
        case .watchScreenConfig(let p):
            envelope = try Envelope(kind: .watchScreenConfig, payloadValue: p, encoder: encoder)
        case .setCompleted(let p):
            envelope = try Envelope(kind: .setCompleted, payloadValue: p, encoder: encoder)
        }
        return try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) throws -> WatchConnectivityMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let envelope: Envelope
        do {
            envelope = try decoder.decode(Envelope.self, from: data)
        } catch {
            throw WatchConnectivityCodecError.malformedEnvelope
        }
        guard let payloadData = envelope.payload else {
            throw WatchConnectivityCodecError.missingPayload(kind: envelope.kind.rawValue)
        }
        do {
            switch envelope.kind {
            case .liveHeartRate:
                return .liveHeartRate(try decoder.decode(LiveHeartRatePayload.self, from: payloadData))
            case .workoutState:
                return .workoutState(try decoder.decode(WorkoutStateSnapshot.self, from: payloadData))
            case .watchScreenConfig:
                return .watchScreenConfig(try decoder.decode(WatchScreenConfig.self, from: payloadData))
            case .setCompleted:
                return .setCompleted(try decoder.decode(SetCompletedEvent.self, from: payloadData))
            }
        } catch let error as WatchConnectivityCodecError {
            throw error
        } catch {
            throw WatchConnectivityCodecError.malformedPayload(kind: envelope.kind.rawValue)
        }
    }

    /// [String: Any] dictionary form used by `WCSession.sendMessage` /
    /// `updateApplicationContext`. Values are opaque `Data` under a single key so
    /// existing plist-restricted transport rules always hold.
    public static func encodeDictionary(_ message: WatchConnectivityMessage) throws -> [String: Any] {
        ["envelope": try encode(message)]
    }

    public static func decodeDictionary(_ dictionary: [String: Any]) throws -> WatchConnectivityMessage {
        guard let data = dictionary["envelope"] as? Data else {
            throw WatchConnectivityCodecError.malformedEnvelope
        }
        return try decode(data)
    }

    // MARK: Envelope wire type (internal)

    private struct Envelope: Codable {
        let kind: Kind
        let payload: Data?

        init(kind: Kind, payloadValue: some Encodable, encoder: JSONEncoder) throws {
            self.kind = kind
            self.payload = try encoder.encode(payloadValue)
        }
    }

    private enum Kind: String, Codable {
        case liveHeartRate
        case workoutState
        case watchScreenConfig
        case setCompleted
    }
}

public enum WatchConnectivityCodecError: Error, Sendable, Equatable {
    case malformedEnvelope
    case missingPayload(kind: String)
    case malformedPayload(kind: String)
}

// MARK: LiveHeartRatePayload (watch → iPhone)

/// Single realtime HR sample pushed from Watch during a workout session.
/// Value is display-only and MUST NOT be logged (§I).
public struct LiveHeartRatePayload: Sendable, Codable, Equatable {
    /// Beats per minute. Rejected if `<= 0` or `> 300`.
    public let bpm: Double
    /// Sample timestamp on the source device.
    public let timestamp: Date
    /// Source device/app name for provenance (e.g. "Apple Watch"). Optional.
    public let sourceName: String?

    public init(bpm: Double, timestamp: Date, sourceName: String?) {
        self.bpm = bpm
        self.timestamp = timestamp
        self.sourceName = sourceName
    }

    /// Physiologically-plausible bpm range gate. Values outside are rejected at
    /// the bridge boundary — never crash, never forward.
    public var isPhysiologicallyPlausible: Bool {
        bpm > 0 && bpm <= 300
    }
}

// MARK: WorkoutStateSnapshot (iPhone → watch)

/// Full workout state pushed via `updateApplicationContext` (latest-wins).
public struct WorkoutStateSnapshot: Sendable, Codable, Equatable {
    public let workoutID: UUID
    public let currentExerciseID: UUID?
    public let currentExerciseName: String?
    public let sets: [PlannedSet]
    /// Elapsed seconds since workout start on the phone clock.
    public let elapsedSeconds: TimeInterval
    /// (completedSetCount, totalSetCount) across the whole workout.
    public let progress: Progress
    public let updatedAt: Date

    public init(
        workoutID: UUID,
        currentExerciseID: UUID?,
        currentExerciseName: String?,
        sets: [PlannedSet],
        elapsedSeconds: TimeInterval,
        progress: Progress,
        updatedAt: Date
    ) {
        self.workoutID = workoutID
        self.currentExerciseID = currentExerciseID
        self.currentExerciseName = currentExerciseName
        self.sets = sets
        self.elapsedSeconds = elapsedSeconds
        self.progress = progress
        self.updatedAt = updatedAt
    }

    public struct PlannedSet: Sendable, Codable, Equatable, Identifiable {
        public let id: UUID
        public let index: Int
        public let targetReps: Int?
        public let targetWeightKg: Double?
        public let isCompleted: Bool

        public init(
            id: UUID,
            index: Int,
            targetReps: Int?,
            targetWeightKg: Double?,
            isCompleted: Bool
        ) {
            self.id = id
            self.index = index
            self.targetReps = targetReps
            self.targetWeightKg = targetWeightKg
            self.isCompleted = isCompleted
        }
    }

    public struct Progress: Sendable, Codable, Equatable {
        public let completedSetCount: Int
        public let totalSetCount: Int

        public init(completedSetCount: Int, totalSetCount: Int) {
            self.completedSetCount = completedSetCount
            self.totalSetCount = totalSetCount
        }
    }
}

// MARK: WatchScreenConfig (iPhone → watch)

/// User-selected layout for the in-workout watch screen. App-configuration,
/// no HK health values (§I).
public struct WatchScreenConfig: Sendable, Codable, Equatable {
    public enum Preset: String, Sendable, Codable, CaseIterable {
        case fullInfo
        case hrFocus
        case list
        case nextFocus
    }

    public enum Module: String, Sendable, Codable, CaseIterable {
        case currentExercise
        case nextExercise
        case setList
        case heartRate
        case timer
        case setProgress
    }

    public let preset: Preset
    public let enabledModules: Set<Module>
    public let updatedAt: Date

    public init(preset: Preset, enabledModules: Set<Module>, updatedAt: Date) {
        self.preset = preset
        self.enabledModules = enabledModules
        self.updatedAt = updatedAt
    }
}

// MARK: SetCompletedEvent (watch → iPhone)

/// User pressed the watch's main "complete set" button. iPhone is source of
/// truth; treat this as an optimistic-forward event to reconcile.
public struct SetCompletedEvent: Sendable, Codable, Equatable {
    public let workoutID: UUID
    public let setID: UUID
    /// Reps actually completed if user adjusted on watch; nil = use planned.
    public let actualReps: Int?
    public let completedAt: Date

    public init(workoutID: UUID, setID: UUID, actualReps: Int?, completedAt: Date) {
        self.workoutID = workoutID
        self.setID = setID
        self.actualReps = actualReps
        self.completedAt = completedAt
    }
}
