public actor TelemetryService {
    public static let shared = TelemetryService()

    private var providers: [any TelemetryProvider] = []

    init() {}

    public func register(_ provider: any TelemetryProvider) {
        providers.append(provider)
    }

    public func track(_ event: TelemetryEvent) {
        for provider in providers {
            provider.track(event)
        }
    }

    /// Forward a MetricKit crash/hang diagnostic to every provider (ADR-0012).
    /// Providers that do not transport diagnostics inherit the no-op default.
    public func record(_ diagnostic: TelemetryDiagnostic) {
        for provider in providers {
            provider.record(diagnostic)
        }
    }

    public nonisolated func trackNonisolated(_ event: TelemetryEvent) {
        Task { await track(event) }
    }

    /// Non-isolated entry point for the MetricKit collector, which delivers
    /// diagnostics on a background queue at launch.
    public nonisolated func recordNonisolated(_ diagnostic: TelemetryDiagnostic) {
        Task { await record(diagnostic) }
    }
}
