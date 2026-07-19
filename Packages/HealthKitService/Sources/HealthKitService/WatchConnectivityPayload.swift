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
//
// Validation contract:
//   - `WatchConnectivityCodec` decode paths run *semantic* validation after
//     structural decode. Missing/wrong fields, non-finite numbers, non-finite
//     dates, out-of-range enums, and kind/payload mismatches all raise typed
//     `WatchConnectivityCodecError`. The delegate never crashes.

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
///    "payload": <payload-as-nested-Data> }`
///
/// Unknown `kind`, missing/malformed `payload`, kind/payload mismatch, and
/// semantically-invalid fields all throw `WatchConnectivityCodecError`
/// (never crash the delegate callback).
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
                let payload = try decoder.decode(LiveHeartRatePayload.self, from: payloadData)
                try payload.validate(expectedKind: envelope.kind.rawValue)
                return .liveHeartRate(payload)
            case .workoutState:
                let payload = try decoder.decode(WorkoutStateSnapshot.self, from: payloadData)
                try payload.validate(expectedKind: envelope.kind.rawValue)
                return .workoutState(payload)
            case .watchScreenConfig:
                let payload = try decoder.decode(WatchScreenConfig.self, from: payloadData)
                try payload.validate(expectedKind: envelope.kind.rawValue)
                return .watchScreenConfig(payload)
            case .setCompleted:
                let payload = try decoder.decode(SetCompletedEvent.self, from: payloadData)
                try payload.validate(expectedKind: envelope.kind.rawValue)
                return .setCompleted(payload)
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
    /// Payload struct decoded but a field failed semantic validation
    /// (out-of-range, non-finite, negative-where-nonneg-required, wrong enum, etc.).
    case invalidField(kind: String, field: String, reason: String)
    /// Payload's self-declared `sampleType` (or another discriminator inside
    /// the payload) disagreed with the envelope `kind`.
    case kindMismatch(envelopeKind: String, payloadKind: String)
}

// MARK: LiveHeartRatePayload (watch → iPhone)

/// Explicit sample-type discriminator embedded in HR payloads. Currently only
/// `heartRate` is defined; future HRV / respiratory-rate work can extend this
/// enum without breaking the wire shape.
public enum LiveSampleType: String, Sendable, Codable, CaseIterable {
    case heartRate
}

/// Single realtime HR sample pushed from Watch during a workout session.
/// Value is display-only and MUST NOT be logged (§I).
public struct LiveHeartRatePayload: Sendable, Codable, Equatable {
    /// Explicit sample-type discriminator (redundant-but-defensive against
    /// envelope corruption; validated against envelope `kind`).
    public let sampleType: LiveSampleType
    /// Beats per minute. Rejected if `<= 0`, `> 300`, or non-finite.
    public let bpm: Double
    /// Sample timestamp on the source device.
    public let timestamp: Date
    /// Source device/app name for provenance (e.g. "Apple Watch"). Optional.
    public let sourceName: String?

    public init(
        sampleType: LiveSampleType = .heartRate,
        bpm: Double,
        timestamp: Date,
        sourceName: String?
    ) {
        self.sampleType = sampleType
        self.bpm = bpm
        self.timestamp = timestamp
        self.sourceName = sourceName
    }

    /// Physiologically-plausible bpm range gate. Values outside are rejected at
    /// the bridge boundary — never crash, never forward.
    public var isPhysiologicallyPlausible: Bool {
        bpm.isFinite && bpm > 0 && bpm <= 300
    }

    fileprivate func validate(expectedKind: String) throws {
        if sampleType != .heartRate {
            throw WatchConnectivityCodecError.kindMismatch(
                envelopeKind: expectedKind,
                payloadKind: sampleType.rawValue
            )
        }
        if !bpm.isFinite {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "bpm", reason: "non-finite"
            )
        }
        if !isPhysiologicallyPlausible {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "bpm", reason: "out-of-range"
            )
        }
        if !timestamp.timeIntervalSince1970.isFinite {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "timestamp", reason: "non-finite"
            )
        }
    }
}

// MARK: WorkoutStateSnapshot (iPhone → watch)

/// Full workout state pushed via `updateApplicationContext` (latest-wins).
public struct WorkoutStateSnapshot: Sendable, Codable, Equatable {
    public let workoutID: UUID
    public let currentExerciseID: UUID?
    public let currentExerciseName: String?
    public let sets: [PlannedSet]
    /// Elapsed seconds since workout start on the phone clock. Must be finite
    /// and `>= 0`.
    public let elapsedSeconds: TimeInterval
    /// (completedSetCount, totalSetCount) across the whole workout. Both must
    /// be `>= 0` and `completed <= total`.
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

    fileprivate func validate(expectedKind: String) throws {
        if !elapsedSeconds.isFinite {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "elapsedSeconds", reason: "non-finite"
            )
        }
        if elapsedSeconds < 0 {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "elapsedSeconds", reason: "negative"
            )
        }
        if progress.completedSetCount < 0 {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "progress.completedSetCount", reason: "negative"
            )
        }
        if progress.totalSetCount < 0 {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "progress.totalSetCount", reason: "negative"
            )
        }
        if progress.completedSetCount > progress.totalSetCount {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind,
                field: "progress",
                reason: "completed > total"
            )
        }
        if !updatedAt.timeIntervalSince1970.isFinite {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "updatedAt", reason: "non-finite"
            )
        }
        for set in sets {
            if set.index < 0 {
                throw WatchConnectivityCodecError.invalidField(
                    kind: expectedKind, field: "sets[].index", reason: "negative"
                )
            }
            if let reps = set.targetReps, reps < 0 {
                throw WatchConnectivityCodecError.invalidField(
                    kind: expectedKind, field: "sets[].targetReps", reason: "negative"
                )
            }
            if let weight = set.targetWeightKg {
                if !weight.isFinite {
                    throw WatchConnectivityCodecError.invalidField(
                        kind: expectedKind, field: "sets[].targetWeightKg", reason: "non-finite"
                    )
                }
                if weight < 0 {
                    throw WatchConnectivityCodecError.invalidField(
                        kind: expectedKind, field: "sets[].targetWeightKg", reason: "negative"
                    )
                }
            }
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

    fileprivate func validate(expectedKind: String) throws {
        if !updatedAt.timeIntervalSince1970.isFinite {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "updatedAt", reason: "non-finite"
            )
        }
    }
}

// MARK: SetCompletedEvent (watch → iPhone)

/// User pressed the watch's main "complete set" button. iPhone is source of
/// truth; treat this as an optimistic-forward event to reconcile.
public struct SetCompletedEvent: Sendable, Codable, Equatable {
    public let workoutID: UUID
    public let setID: UUID
    /// Reps actually completed if user adjusted on watch; nil = use planned.
    /// Rejected if negative.
    public let actualReps: Int?
    public let completedAt: Date

    public init(workoutID: UUID, setID: UUID, actualReps: Int?, completedAt: Date) {
        self.workoutID = workoutID
        self.setID = setID
        self.actualReps = actualReps
        self.completedAt = completedAt
    }

    fileprivate func validate(expectedKind: String) throws {
        if let reps = actualReps, reps < 0 {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "actualReps", reason: "negative"
            )
        }
        if !completedAt.timeIntervalSince1970.isFinite {
            throw WatchConnectivityCodecError.invalidField(
                kind: expectedKind, field: "completedAt", reason: "non-finite"
            )
        }
    }
}
