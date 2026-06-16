import os

public struct ConsoleTelemetryProvider: TelemetryProvider {
    private let logger = Logger(subsystem: "com.vitalstride", category: "Telemetry")

    public init() {}

    public func track(_ event: TelemetryEvent) {
        logger.info("[Telemetry] \(event.formattedString, privacy: .public)")
    }
}
