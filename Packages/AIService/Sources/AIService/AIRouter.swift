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

    // MARK: - Init

    public init(
        providers: [RegisteredProvider],
        policy: [AITaskKind: TaskRequirements] = AIRouter.defaultPolicy,
        deviceTier: @escaping @Sendable () -> DeviceTier = { DeviceTier.detect() }
    ) {
        self.providers = providers
        self.policy = policy
        self.deviceTierProvider = deviceTier
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
    ///   structured JSON; carries health data.
    /// - `.trainingAdvice`: interactive card in Training tab; structured JSON with
    ///   muscle groups & exercises; carries workout data.
    /// - `.dataTrend`: interactive on Data tab; structured JSON summarizing a sample
    ///   type; carries health values.
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
            quality: .medium,
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
            quality: .medium,
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
        let chain = buildChain(for: kind)
        return try await chain.chat(messages: messages, model: model)
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
        let ordered = orderedProviders(for: kind)
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
}
