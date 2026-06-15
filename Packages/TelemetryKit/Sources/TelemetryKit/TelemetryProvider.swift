public protocol TelemetryProvider: Sendable {
    func track(_ event: TelemetryEvent)
}
