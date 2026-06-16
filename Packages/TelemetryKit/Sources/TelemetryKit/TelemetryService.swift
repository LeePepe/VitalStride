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

    public nonisolated func trackNonisolated(_ event: TelemetryEvent) {
        Task { await track(event) }
    }
}
