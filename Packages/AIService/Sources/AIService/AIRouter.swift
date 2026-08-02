import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vitalstride.aiservice", category: "AIRouter")

/// Central AI routing surface. Callers declare only a `AITaskKind`; the router picks
/// a provider ordering for the current device tier and delegates execution to
/// `AIProviderChain`. Chain semantics (skip unavailable → try in order → fall back on
/// runtime error) are preserved — the router only decides which providers, in which
/// order, participate in the chain for this call.
///
/// Constitution/spec anchors:
/// - FR-001: caller only passes `kind` + `messages` (no provider handles).
/// - FR-003: central policy table lives here, not scattered across callers.
/// - FR-004: `AIRouter` delegates to `AIProviderChain`, does NOT replace it.
/// - FR-005: on-device arm probability = 0 on `cloudOnly` devices (strengthens
///   "chain order not reversed", never weakens it).
public struct AIRouter: Sendable {

    // MARK: - Nested types

    /// A named provider the router can pick from. `AIRouter` selects an ordering of
    /// these per request; the resulting subset is wrapped in `AIProviderChain` for
    /// execution.
    public struct RegisteredProvider: Sendable {
        public let name: String
        /// Whether this provider is technically usable right now (e.g. key present,
        /// OS capability available). Same shape as `AIProviderChain.ProviderEntry.isAvailable`.
        public let isAvailable: @Sendable () -> Bool
        /// Whether this provider runs on-device (Apple Intelligence path). Used by
        /// the router to enforce FR-005 on `cloudOnly` devices.
        public let isOnDevice: Bool
        /// Highest `QualityClass` this provider can plausibly satisfy. Used by the
        /// central policy to match `TaskRequirements.quality` — a provider is only
        /// eligible if `maxQuality >= requirements.quality`. This is what makes
        /// `.chat` (quality=.high) skip the on-device arm (maxQuality=.medium) and
        /// pick the cloud provider directly, without reversing chain order for
        /// tasks that don't need it.
        public let maxQuality: QualityClass
        public let provider: any AIProvider

        public init(
            name: String,
            isAvailable: @escaping @Sendable () -> Bool,
            isOnDevice: Bool,
            maxQuality: QualityClass,
            provider: any AIProvider
        ) {
            self.name = name
            self.isAvailable = isAvailable
            self.isOnDevice = isOnDevice
            self.maxQuality = maxQuality
            self.provider = provider
        }
    }

    // MARK: - State

    private let providers: [RegisteredProvider]
    private let policy: [AITaskKind: TaskRequirements]
    private let deviceTierProvider: @Sendable () -> DeviceTier
    private let signalSink: any RoutingSignalSink
    /// TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
    /// Optional on purpose: `nil` means raw prompt/response text is never even
    /// built, so the default router carries no health data anywhere (FR-018).
    private let rawDebugSink: (any LocalOnlyRawDebugSink)?
    private let schemaValidator: (@Sendable (AITaskKind, String) -> Bool)?

    // MARK: - Shadow sampling (US3 / spec 019 Stage 4)
    private let shadowSampler: any ShadowSampler
    private let shadowSignalSink: any ShadowSignalSink
    /// TEMP-PRELAUNCH: 上架前移除——原始候选响应仅供发布前单用户调试（宪法 I）
    /// `nil` (default) means the router never even builds the raw candidate
    /// response string when a shadow dual-run fires — mirrors `rawDebugSink`.
    private let shadowPairSink: (any LocalOnlyShadowPairSink)?

    // MARK: - Bandit routing (US4 / spec 019 Stage 5)
    /// Optional bandit that picks the primary provider name for a given
    /// `(kind, deviceTier)`. `nil` = Stage 1 static routing (Day-1 zero
    /// regression is preserved without needing the bandit at all).
    private let bandit: AIRoutingBandit?
    /// Optional persistent store for bandit arm state. Written to
    /// best-effort after every `execute` via a detached Task — writes never
    /// block the caller or affect the returned response (FR-008 inherited).
    private let banditRepo: any BanditArmStateRepository

    // MARK: - Init

    /// - Parameters:
    ///   - signalSink: consumer for the bypass `RoutingSignal` emitted after
    ///     every `execute` call. `nil` (the default) installs a `NoOpRoutingSignalSink`
    ///     — the router keeps the storage non-optional so the hot path avoids an
    ///     optional check. Real sinks are wired at app-target composition (spec
    ///     019 Stage 3c).
    ///   - rawDebugSink: TEMP-PRELAUNCH controlled exception (spec 019
    ///     FR-015/016/018). `nil` (the default) means the router never builds
    ///     the raw prompt/response strings at all. Supplying a sink is an
    ///     explicit assertion that it writes only into the device-local
    ///     `cloudKitDatabase: .none` store — see `LocalOnlyRawDebugSink`.
    ///     MUST be removed together with the protocol before App Store
    ///     submission (FR-017 / SC-007).
    ///   - schemaValidator: optional per-response validator returning `true` iff
    ///     the response content parses/validates against the caller's schema.
    ///     `nil` or `false` → `schemaValid=false` on the emitted signal. The
    ///     router does not decode — validation stays a caller concern (FR-003 /
    ///     constitution V: router doesn't replace provider semantics).
    ///   - shadowSampler: decides per-call whether a shadow dual-run should
    ///     fire (spec 019 US3 / FR-010). Default `NeverShadowSampler` = no
    ///     dual-runs, preserving Stage 3 behavior.
    ///   - shadowSignalSink: consumer for `ShadowSignal` values. Fire-and-forget
    ///     just like `signalSink`. Default is a no-op.
    ///   - shadowPairSink: TEMP-PRELAUNCH raw shadow-pair sink (FR-011 offline
    ///     evaluation input). `nil` means the raw candidate response text is
    ///     never even built. Explicit opt-in only, at the composition root.
    ///   - bandit: optional `AIRoutingBandit` that picks the primary
    ///     provider name for `(kind, deviceTier)`. `nil` (the default)
    ///     preserves Stage 1 static routing exactly — Day-1 zero regression
    ///     without needing bandit state at all (spec 019 SC-006, FR-013).
    ///   - banditRepo: optional persistent store the router will `loadAll`
    ///     before each pick and `upsert` (fire-and-forget) with the observed
    ///     reward after each call. `nil` installs `NoOpBanditArmStateRepository`
    ///     so `bandit` degrades gracefully to prior-only behavior.
    public init(
        providers: [RegisteredProvider],
        policy: [AITaskKind: TaskRequirements] = AIRouter.defaultPolicy,
        deviceTier: @escaping @Sendable () -> DeviceTier = { DeviceTier.detect() },
        signalSink: (any RoutingSignalSink)? = nil,
        rawDebugSink: (any LocalOnlyRawDebugSink)? = nil,
        schemaValidator: (@Sendable (AITaskKind, String) -> Bool)? = nil,
        shadowSampler: (any ShadowSampler)? = nil,
        shadowSignalSink: (any ShadowSignalSink)? = nil,
        shadowPairSink: (any LocalOnlyShadowPairSink)? = nil,
        bandit: AIRoutingBandit? = nil,
        banditRepo: (any BanditArmStateRepository)? = nil
    ) {
        self.providers = providers
        self.policy = policy
        self.deviceTierProvider = deviceTier
        self.signalSink = signalSink ?? NoOpRoutingSignalSink()
        self.rawDebugSink = rawDebugSink
        self.schemaValidator = schemaValidator
        self.shadowSampler = shadowSampler ?? NeverShadowSampler()
        self.shadowSignalSink = shadowSignalSink ?? NoOpShadowSignalSink()
        self.shadowPairSink = shadowPairSink
        self.bandit = bandit
        self.banditRepo = banditRepo ?? NoOpBanditArmStateRepository()
    }

    /// Build a default `AIRouter` mirroring `AIProviderChain.makeDefault`:
    /// Apple Intelligence first, Zhipu as cloud fallback. Provided so caller
    /// migration in Stage 2 can drop `AIProviderChain.makeDefault` and use this
    /// factory directly.
    ///
    /// Capability metadata:
    /// - `apple_intelligence.maxQuality = .medium` — on-device Foundation Model
    ///   handles substitutions, short summaries, structured JSON well, but
    ///   long-form high-quality chat is expected to be routed to the cloud tier.
    /// - `zhipu.maxQuality = .high` — cloud GLM handles the full quality range.
    public static func makeDefault(zhipuAPIKey: String?) -> AIRouter {
        var providers: [RegisteredProvider] = []

        providers.append(RegisteredProvider(
            name: "apple_intelligence",
            isAvailable: { AppleIntelligenceProvider.isAvailable },
            isOnDevice: true,
            maxQuality: .medium,
            provider: AppleIntelligenceProvider()
        ))

        if let key = zhipuAPIKey {
            providers.append(RegisteredProvider(
                name: "zhipu",
                isAvailable: { !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                isOnDevice: false,
                maxQuality: .high,
                provider: ZhipuProvider(apiKey: key)
            ))
        }

        return AIRouter(providers: providers)
    }

    // MARK: - Central policy table

    /// The single source of truth for `kind → requirements`. Adding a new kind:
    /// add a case to `AITaskKind` AND an entry here. Callers never see this table.
    ///
    /// Rationale per entry:
    /// - `.chat`: interactive UI, long-form quality, no strict schema, may echo user
    ///   text that includes health/training numbers.
    /// - `.overviewInsights`: background pre-warm on the Overview tab; multi-field
    ///   structured JSON; carries health data. `quality=.high` preserves the
    ///   pre-migration cloud-GLM behavior (spec 019 Stage 2 acceptance SC-004) —
    ///   the on-device Foundation Model's `maxQuality=.medium` isn't yet trusted
    ///   for the multi-card synthesis this feature ships.
    /// - `.trainingAdvice`: interactive card in Training tab; structured JSON with
    ///   muscle groups & exercises; carries workout data.
    /// - `.dataTrend`: interactive on Data tab; structured JSON summarizing a sample
    ///   type; carries health values. `quality=.high` for the same reason as
    ///   `.overviewInsights` — the pre-migration site always went to cloud GLM.
    /// - `.substitute`: mid-workout swap, interactive, short factual reply, no schema,
    ///   no raw health data (just exercise names).
    public static let defaultPolicy: [AITaskKind: TaskRequirements] = [
        .chat: TaskRequirements(
            latency: .interactive,
            quality: .high,
            structured: false,
            carriesHealthData: true
        ),
        .overviewInsights: TaskRequirements(
            latency: .background,
            quality: .high,
            structured: true,
            carriesHealthData: true
        ),
        .trainingAdvice: TaskRequirements(
            latency: .interactive,
            quality: .high,
            structured: true,
            carriesHealthData: true
        ),
        .dataTrend: TaskRequirements(
            latency: .interactive,
            quality: .high,
            structured: true,
            carriesHealthData: true
        ),
        .substitute: TaskRequirements(
            latency: .interactive,
            quality: .low,
            structured: false,
            carriesHealthData: false
        ),
    ]

    /// Safe default for an unknown / newly-added-but-unmapped kind. Chosen so an
    /// unmapped kind still works but with the least aggressive path: background
    /// priority, medium quality, no structured decode assumption, health-data safe.
    /// Router logs a warning; caller MUST NOT crash. (spec Edge Case: "未知 kind")
    public static let safeDefaultRequirements = TaskRequirements(
        latency: .background,
        quality: .medium,
        structured: false,
        carriesHealthData: true
    )

    // MARK: - Public API

    /// Execute an AI request. The caller declares only the task identity. The router
    /// resolves policy + device tier → provider ordering → delegates to
    /// `AIProviderChain`.
    ///
    /// - Parameters:
    ///   - kind: what the caller is doing (identity, not policy).
    ///   - messages: the chat message list.
    ///   - model: optional model hint passed through to the selected provider.
    /// - Returns: `ChatResponse` from the first provider that succeeds.
    /// - Throws: `AIServiceError.noProviderAvailable` if no eligible provider is
    ///   currently available, or the last provider's error if all eligible providers
    ///   fail at runtime.
    public func execute(
        kind: AITaskKind,
        messages: [ChatMessage],
        model: String? = nil
    ) async throws -> ChatResponse {
        let baseOrdered = orderedProviders(for: kind)
        let tier = deviceTierProvider()

        // Bandit hook (spec 019 Stage 5 / FR-012–014). The bandit picks the
        // PRIMARY provider name; the surviving order after capability filter
        // is preserved for fallback. This preserves the constitution V red
        // line "chain 顺序不得反转" — the chain still walks providers in
        // order; the bandit only decides which of the still-eligible arms
        // heads the list. Any arm the router already dropped (cloudOnly
        // pruning, capability mismatch) is invisible to the bandit —
        // FR-012/013's "cloudOnly on-device arm probability = 0" is
        // enforced BEFORE `selectProvider` is called.
        let arms: [BanditArmState]
        if bandit != nil {
            arms = await banditRepo.loadAll()
        } else {
            arms = []
        }
        let ordered = banditReorder(
            base: baseOrdered,
            kind: kind,
            tier: tier,
            arms: arms
        )
        let chain = buildChain(from: ordered)
        let clock = ContinuousClock()
        let start = clock.now
        // `chatWithOutcome` reports the provider that ACTUALLY served the call.
        // Guessing `ordered.first(where: { $0.isAvailable() })` here would be
        // wrong whenever the chain falls back past a failing provider — it
        // would pin this call's latency/schemaValid onto the arm that failed,
        // corrupting exactly the fallback cases spec 019 wants to measure.
        let outcome = try await chain.chatWithOutcome(messages: messages, model: model)
        let response = outcome.response
        let elapsed = clock.now - start
        let latencyMs = Int(elapsed.components.seconds * 1_000
            + elapsed.components.attoseconds / 1_000_000_000_000_000)

        let schemaValid = schemaValidator?(kind, response.content) ?? false

        let signal = RoutingSignal(
            kind: kind,
            provider: outcome.providerName,
            deviceTier: tier,
            latencyMs: latencyMs,
            schemaValid: schemaValid,
            accepted: nil,
            timestamp: Date()
        )

        // FR-008 fire-and-forget: sink failures / delays MUST NOT block or
        // change the user-facing return value. Detached Task + `try?` swallow.
        // `signal` carries routing metadata only — no health data crosses this
        // boundary, so an arbitrary conformer is safe here.
        let sink = signalSink
        Task.detached(priority: .background) {
            try? await sink.record(signal)
        }

        // Bandit reward feedback (spec 019 FR-013 / Stage 5).
        //
        // Fire-and-forget: `banditRepo.upsert` inherits Stage 3 FR-008 —
        // slow or failing writes never block the user-facing return path.
        // The `accepted` signal is `nil` here on purpose; the Stage 3c
        // `RoutingSignalSink` pipeline provides the acceptance channel
        // separately. Bandit reward on this hot path uses only schema
        // validity + optional offline score (offlineScore=nil unless a
        // future Stage 4 hook feeds it in).
        //
        // Reward inputs are Bool + Bool? + Double? — no HealthKit values
        // touch the bandit (constitution I). The `upsert` delta is the
        // reward for a single observation; the repo accumulates.
        if let bandit {
            let reward = bandit.computeReward(
                schemaValid: schemaValid,
                accepted: nil,
                offlineScore: nil
            )
            let repo = banditRepo
            let servedProvider = outcome.providerName
            Task.detached(priority: .background) {
                try? await repo.upsert(
                    kind: kind,
                    deviceTier: tier,
                    provider: servedProvider,
                    deltaCount: 1,
                    deltaReward: reward
                )
            }
        }

        // TEMP-PRELAUNCH: 上架前移除——原始健康值仅供发布前单用户调试（宪法 I）
        //
        // FR-018: the raw prompt/response may embed HealthKit-derived values.
        // They are built ONLY when a `LocalOnlyRawDebugSink` was explicitly
        // injected, and handed ONLY to that sink — whose contract is
        // device-local `cloudKitDatabase: .none` storage. With no such sink
        // (the default) this block does not execute and the raw strings are
        // never materialized. They are never printed, never sent through
        // os_log / Logger, never forwarded to Aptabase or GlitchTip.
        if let rawDebugSink {
            let payload = RawDebugPayload(
                prompt: messages
                    .map { "\($0.role): \($0.content)" }
                    .joined(separator: "\n"),
                response: response.content
            )
            Task.detached(priority: .background) {
                try? await rawDebugSink.recordRawDebug(payload, for: signal)
            }
        }

        // Shadow dual-run (spec 019 US3 / FR-010).
        //
        // Fires when (a) the sampler says yes for this kind AND (b) a second
        // distinct eligible provider actually exists in `ordered`. The main
        // result has already been captured — everything below happens off the
        // caller's critical path and is best-effort.
        maybeFireShadow(
            kind: kind,
            messages: messages,
            model: model,
            ordered: ordered,
            mainProviderName: outcome.providerName,
            mainLatencyMs: latencyMs,
            mainResponse: response,
            tier: tier
        )

        return response
    }

    /// Streaming counterpart of `execute`. Same routing rules; delegates to
    /// `AIProviderChain.chatStream`.
    public func executeStream(
        kind: AITaskKind,
        messages: [ChatMessage],
        model: String? = nil
    ) -> AsyncThrowingStream<ChatStreamChunk, Error> {
        let chain = buildChain(for: kind)
        return chain.chatStream(messages: messages, model: model)
    }

    // MARK: - Introspection (for tests + signal collection later)

    /// Returns the ordered list of provider names the router would try for `(kind,
    /// current device tier)`, filtered by current `isAvailable()`. First name is the
    /// primary pick. Empty means no provider is eligible.
    ///
    /// This is stable, deterministic, and does not perform any network I/O — safe
    /// to call from tests to assert routing decisions (spec's Independent Test).
    public func plannedProviderOrder(for kind: AITaskKind) -> [String] {
        orderedProviders(for: kind)
            .filter { $0.isAvailable() }
            .map { $0.name }
    }

    /// Returns the `TaskRequirements` for `kind`, or the safe default (with a warning
    /// log) if `kind` is not in the policy table.
    public func requirements(for kind: AITaskKind) -> TaskRequirements {
        if let picture = policy[kind] {
            return picture
        }
        logger.warning("Unknown AITaskKind \(kind.rawValue, privacy: .public) has no policy entry; using safe default (background/medium)")
        return Self.safeDefaultRequirements
    }

    // MARK: - Internals

    /// Build the `AIProviderChain` this call will delegate to. Chain semantics are
    /// unchanged — the router only decides which providers, in which order,
    /// participate for this `kind` on the current device tier.
    private func buildChain(for kind: AITaskKind) -> AIProviderChain {
        buildChain(from: orderedProviders(for: kind))
    }

    private func buildChain(from ordered: [RegisteredProvider]) -> AIProviderChain {
        let entries = ordered.map { registered in
            AIProviderChain.ProviderEntry(
                name: registered.name,
                isAvailable: registered.isAvailable,
                provider: registered.provider
            )
        }
        return AIProviderChain(entries: entries)
    }

    /// Core routing decision. Returns providers in try-order.
    ///
    /// Rules (in this exact order):
    /// 1. Look up `requirements(for: kind)` (safe default on miss).
    /// 2. Read current `DeviceTier`. On `.cloudOnly`, drop every `isOnDevice`
    ///    provider — enforces FR-005 that the on-device arm probability = 0 on
    ///    incapable devices.
    /// 3. Capability match (FR-003): drop any provider whose `maxQuality` is
    ///    below the requirement. `.chat` (quality=.high) prunes the on-device
    ///    arm (maxQuality=.medium); `.substitute` (quality=.low) keeps both.
    /// 4. Sort surviving providers **without reversing chain order** (FR-004):
    ///    stable-preserve their original registration order, then move the
    ///    on-device arm ahead of cloud when both are still present. That means
    ///    `.substitute` on a capable device sees `[apple, zhipu]` — on-device
    ///    first. `.chat` sees `[zhipu]` because apple was pruned by capability,
    ///    not by re-sorting apple below zhipu.
    ///
    /// This preserves the constitution red line "Apple Intelligence 本地优先 +
    /// 智谱 GLM fallback 的 chain 顺序不得反转" — pruning an ineligible arm is
    /// allowed; putting cloud ahead of an eligible on-device arm would not be.
    private func orderedProviders(for kind: AITaskKind) -> [RegisteredProvider] {
        let tier = deviceTierProvider()
        let requirements = requirements(for: kind)

        // Step 2: device-tier filter (FR-005 on cloudOnly).
        let tierFiltered: [RegisteredProvider]
        switch tier {
        case .cloudOnly:
            tierFiltered = providers.filter { !$0.isOnDevice }
        case .appleIntelligenceCapable:
            tierFiltered = providers
        }

        // Step 3: capability match — drop providers that cannot meet the
        // requirement's quality bar. This is what makes `.chat` (`.high`) skip
        // the on-device arm and pick the cloud provider directly.
        let capable = tierFiltered.filter { $0.maxQuality >= requirements.quality }

        // Step 4: stable ordering — on-device first among the survivors.
        // Uses `enumerated()` to keep a deterministic tiebreaker so registration
        // order is preserved within the same tier bucket (Swift's `sorted` is
        // not stable).
        let indexed = capable.enumerated().map { (offset: $0.offset, provider: $0.element) }
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.provider.isOnDevice != rhs.provider.isOnDevice {
                return lhs.provider.isOnDevice && !rhs.provider.isOnDevice
            }
            return lhs.offset < rhs.offset
        }
        return sorted.map { $0.provider }
    }

    // MARK: - Bandit-driven reorder (spec 019 Stage 5)

    /// Given the base ordering produced by `orderedProviders(for:)`, ask the
    /// bandit which of those still-eligible providers should be the primary,
    /// and reorder `base` to put that provider first. If no bandit is
    /// installed OR the base ordering has zero/one entries, returns `base`
    /// unchanged — Stage 1 static routing is preserved.
    ///
    /// Reorder semantics:
    /// - `available = base` (already tier + capability filtered).
    /// - `pick = bandit.selectProvider(kind, tier, arms, available.map { $0.name })`.
    /// - If `pick` matches a non-first entry in `base`, that entry is
    ///   moved to the head; the rest keep their relative order (stable
    ///   partition). This preserves chain fallback semantics — the pruned
    ///   or reordered-below arms are still tried in their original order
    ///   if the primary fails.
    ///
    /// Constitution V: this is NOT a chain reversal. Chain reversal would
    /// put a low-quality/pruned arm ahead of an eligible one. The bandit
    /// only reorders WITHIN the already-eligible set that `orderedProviders`
    /// produced — every arm the bandit could pick was already going to run
    /// in the chain.
    private func banditReorder(
        base: [RegisteredProvider],
        kind: AITaskKind,
        tier: DeviceTier,
        arms: [BanditArmState]
    ) -> [RegisteredProvider] {
        guard let bandit else { return base }
        guard base.count > 1 else { return base }
        let available = base.map { $0.name }
        let pick = bandit.selectProvider(
            kind: kind,
            deviceTier: tier,
            arms: arms,
            availableProviders: available
        )
        guard let idx = base.firstIndex(where: { $0.name == pick }), idx > 0 else {
            return base
        }
        var reordered = base
        let chosen = reordered.remove(at: idx)
        reordered.insert(chosen, at: 0)
        return reordered
    }



    /// Runs the shadow dual-run if the sampler says yes and a distinct
    /// candidate provider actually exists. Everything below `Task.detached`
    /// runs off the caller's critical path — the main result has already been
    /// returned by `execute` before this fires.
    ///
    /// A distinct candidate is defined as: the first *available* provider in
    /// `ordered` whose name differs from `mainProviderName`. Rationale — if the
    /// only eligible provider IS the one that served, there's nothing to
    /// compare, and running the same provider twice would only inflate cost
    /// and pollute the signal.
    private func maybeFireShadow(
        kind: AITaskKind,
        messages: [ChatMessage],
        model: String?,
        ordered: [RegisteredProvider],
        mainProviderName: String,
        mainLatencyMs: Int,
        mainResponse: ChatResponse,
        tier: DeviceTier
    ) {
        guard shadowSampler.shouldSample(kind: kind) else { return }

        // Pick the first available provider that isn't the main one. If none,
        // silently skip — no shadow signal for a call with no comparison.
        guard let candidate = ordered.first(where: {
            $0.name != mainProviderName && $0.isAvailable()
        }) else {
            return
        }

        let sink = shadowSignalSink
        let pairSink = shadowPairSink
        let candidateName = candidate.name
        let candidateProvider = candidate.provider
        let mainName = mainProviderName
        let mainContent = mainResponse.content

        Task.detached(priority: .background) {
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let response = try await candidateProvider.chat(messages: messages, model: model)
                let elapsed = clock.now - start
                let candidateLatencyMs = Int(elapsed.components.seconds * 1_000
                    + elapsed.components.attoseconds / 1_000_000_000_000_000)

                let signal = ShadowSignal(
                    kind: kind,
                    mainProvider: mainName,
                    candidateProvider: candidateName,
                    deviceTier: tier,
                    mainLatencyMs: mainLatencyMs,
                    candidateLatencyMs: candidateLatencyMs,
                    candidateSucceeded: true,
                    candidateErrorCategory: nil,
                    timestamp: Date()
                )
                try? await sink.recordShadow(signal)

                // TEMP-PRELAUNCH: raw shadow-pair only handed to an explicit
                // opt-in sink; never materialized otherwise.
                if let pairSink {
                    let payload = ShadowPairPayload(
                        mainResponse: mainContent,
                        candidateResponse: response.content
                    )
                    try? await pairSink.recordShadowPair(payload, for: signal)
                }
            } catch {
                // FR-010 / spec edge case: candidate failure MUST NOT touch
                // the already-returned main result. Record a shadowFailed
                // signal and move on.
                let signal = ShadowSignal(
                    kind: kind,
                    mainProvider: mainName,
                    candidateProvider: candidateName,
                    deviceTier: tier,
                    mainLatencyMs: mainLatencyMs,
                    candidateLatencyMs: nil,
                    candidateSucceeded: false,
                    candidateErrorCategory: AIRouter.errorCategory(error),
                    timestamp: Date()
                )
                try? await sink.recordShadow(signal)
            }
        }
    }

    /// Coarse error classifier for shadow candidate failures. Mirrors the
    /// private version in `AIProviderChain` — kept in sync intentionally so
    /// downstream aggregation buckets stay comparable.
    private static func errorCategory(_ error: Error) -> String {
        if let aiError = error as? AIServiceError {
            switch aiError {
            case .noProviderAvailable: return "noProviderAvailable"
            case .networkError: return "networkError"
            case .httpError(let code): return "httpError(\(code))"
            case .missingAPIKey: return "missingAPIKey"
            case .responseParsingFailed: return "responseParsingFailed"
            case .streamingInterrupted: return "streamingInterrupted"
            }
        }
        if error is URLError { return "networkError" }
        return "unknown"
    }
}
