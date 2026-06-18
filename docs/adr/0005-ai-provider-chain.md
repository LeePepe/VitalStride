# ADR-0005: AI ProviderChain (Apple Intelligence Primary, Zhipu Fallback)

**Status**: Accepted
**Date**: 2026-06-18 (backfilled)
**Deciders**: tianpli (project owner)

## Context

VitalStride uses AI for two product surfaces:

- **Overview insights** — personalized health summary cards (HeadlineBar + insight cards) on the home screen.
- **Training advice / data analysis** — AI-driven commentary in the Workout and Data tabs.

The requirements pull in opposite directions:

- **Privacy-first** — health data should not leave the device when avoidable. Apple Intelligence runs on-device for many requests, no network round-trip, no third-party data exposure.
- **Capability and availability** — Apple Intelligence is only available on capable hardware, in supported regions, and for certain query types. When unavailable or insufficient, the user still expects insights to show up.

A single provider couldn't satisfy both. A naive `if-else` per call site would scatter capability detection across the codebase and make caching/quality measurement impossible.

## Decision

Introduce an **`AIProviderChain`** abstraction in the `AIService` SPM package:

### Components

- **`AIProvider` protocol** — common surface: produce an `AIAnalysisResponse` (headline + insights) from a typed prompt request.
- **`AppleIntelligenceProvider`** — primary. On-device when available; raises `.notAvailable` cleanly when capability check fails.
- **`ZhipuProvider`** — fallback. Network-bound, requires user-configured API key from Settings.
- **`AIProviderChain`** — orders providers by priority, walks the chain, returns the first success. Records the source provider on the response for observability.
- **`AIAnalysisResponse` + insight cache (`AIInsightsCacheEntry` in `VitalModels`)** — uniform response shape so cached insights can be served regardless of which provider produced them.

### Behavior

- Same prompt + same context → same `AIAnalysisResponse` shape regardless of provider.
- Cache hit short-circuits the chain entirely.
- A "fresh" insight that turns out to repeat the cached headline still surfaces via `HeadlineBar` so the user knows a refresh happened.
- Provider chain is configurable at startup; tests inject mock providers.

### Privacy posture

- Health values that go into a prompt are **sanitized** before being sent to Zhipu (or any network provider): exact heart rate or weight numbers are bucketed, identifiers stripped. Apple Intelligence sees the raw values because it stays on-device.
- The provider name on `AIAnalysisResponse` is shown to the user (or available via debug) so they know whether a given insight was on-device or cloud-sourced.

## Consequences

### Positive
- On-device-first → most insights are free, instant, and private.
- Cloud fallback → product still works on older hardware or in regions without Apple Intelligence.
- Single cache layer regardless of source — quality comparison and A/B is possible.
- Adding a third provider (OpenAI, Anthropic, local LLM) is a 50-line file plus a chain registration.

### Negative
- Prompt engineering must work across two model families with different strengths. Some prompt drift expected.
- Privacy-conscious sanitization adds complexity to every prompt builder.
- Two error surfaces (`AIServiceError.notAvailable`, `.networkFailure`) instead of one.
- Telemetry needs to record provider used per response, or quality regressions get blamed on the wrong model.

### Trade-offs accepted
- We do not run providers in parallel and pick the best response — would double cost and complicate caching. First-success wins.
- Zhipu chosen as fallback over OpenAI for now because of better China-region availability for the project owner. Easy to swap.

## Implementation references

- `Packages/AIService/Sources/AIService/AIProvider.swift`
- `Packages/AIService/Sources/AIService/AIProviderChain.swift`
- `Packages/AIService/Sources/AIService/AppleIntelligenceProvider.swift`
- `Packages/AIService/Sources/AIService/ZhipuProvider.swift`
- `Packages/AIService/Sources/AIService/Models.swift` (`AIAnalysisResponse`)
- `Packages/AIService/Tests/AIServiceTests/AIProviderChainTests.swift`
- `Packages/VitalModels/Sources/VitalModels/Models/` (`AIInsightsCacheEntry`)

## Revisit triggers

- A provider becomes unavailable (deprecation, key revocation).
- Quality gap between providers widens enough that "first success" becomes wrong.
- New on-device model (e.g. Apple's next generation) changes the capability matrix.
- User asks for explicit provider choice in Settings.
