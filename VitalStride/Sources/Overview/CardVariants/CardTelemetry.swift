import os

private let logger = Logger(subsystem: "com.vitalstride", category: "OverviewCard")

enum CardTelemetry {
    static func recordRendered(size: String, type: String) {
        logger.info("overview_card_rendered size=\(size, privacy: .public) type=\(type, privacy: .public)")
    }

    static func recordRenderFailed(size: String, type: String) {
        logger.warning("overview_card_render_failed size=\(size, privacy: .public) type=\(type, privacy: .public)")
    }
}
