import os

private let logger = Logger(subsystem: "com.vitalstride", category: "OverviewCard")

enum CardTelemetry {
    static func recordRendered(size: CardSize, type: CardType) {
        logger.info("overview_card_rendered size=\(size.rawValue, privacy: .public) type=\(type.rawValue, privacy: .public)")
    }

    static func recordRenderFailed(size: CardSize?, type: CardType?) {
        let sizeLabel = size?.rawValue ?? "invalid"
        let typeLabel = type?.rawValue ?? "invalid"
        logger.warning("overview_card_render_failed size=\(sizeLabel, privacy: .public) type=\(typeLabel, privacy: .public)")
    }
}
