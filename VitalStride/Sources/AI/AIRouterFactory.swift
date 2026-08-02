import AIService
import Foundation
import SwiftData

/// App-target composition helper for `AIRouter`. Spec 019 Stage 3c (T017/T018)
/// wires a `RoutingSignalStore` sink into every AI call site — the 11 callers
/// (`ActiveWorkoutView`, `AIChatView`, overview / training-advice / data-trend
/// insight sites) previously invoked `AIRouter.makeDefault(zhipuAPIKey:)`
/// directly and never emitted a `RoutingSignal`.
///
/// This factory sits in the app target so:
///   1. AIService stays free of VitalModels / `ModelContainer` — the sink
///      protocol keeps that boundary clean (see `RoutingSignalStore`).
///   2. Every caller reaches the router the same way, so any future sink
///      change (batching, sampling, retention) is a one-file diff here.
///
/// Passing `signalSink: nil` (the default) preserves pre-Stage-3c behaviour
/// — the router installs its own `NoOpRoutingSignalSink` and no rows are
/// written. Callers that opt into the sink pass the store built in
/// `VitalStrideApp` and shared across the app.
enum AIRouterFactory {
    static func makeDefault(
        zhipuAPIKey: String?,
        signalSink: (any RoutingSignalSink)? = nil
    ) -> AIRouter {
        var providers: [AIRouter.RegisteredProvider] = []

        providers.append(AIRouter.RegisteredProvider(
            name: "apple_intelligence",
            isAvailable: { AppleIntelligenceProvider.isAvailable },
            isOnDevice: true,
            maxQuality: .medium,
            provider: AppleIntelligenceProvider()
        ))

        if let key = zhipuAPIKey {
            providers.append(AIRouter.RegisteredProvider(
                name: "zhipu",
                isAvailable: { !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                isOnDevice: false,
                maxQuality: .high,
                provider: ZhipuProvider(apiKey: key)
            ))
        }

        return AIRouter(providers: providers, signalSink: signalSink)
    }
}
