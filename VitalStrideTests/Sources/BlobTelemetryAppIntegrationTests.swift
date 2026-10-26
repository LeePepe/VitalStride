import Testing
@testable import VitalStride
import TelemetryKit

struct BlobTelemetryAppIntegrationTests {
    @Test("App telemetry bootstrap resolves a valid Blob configuration")
    func resolvesConfiguredProvider() {
        let provider = AppTelemetryBootstrap.makeProvider(
            infoDictionary: [
                "LokiKitBlobEndpoint": "https://example.invalid/container",
                "LokiKitBlobSAS": "sv=2023-11-03&sr=c&sig=test"
            ],
            version: "1.1",
            build: "7",
            isDebugBuild: true
        )

        #expect(provider != nil)
    }

    @Test("App telemetry bootstrap disables missing or unresolved configuration")
    func disablesMissingConfiguration() {
        #expect(
            AppTelemetryBootstrap.makeProvider(
                infoDictionary: [:],
                version: "1.1",
                build: "7",
                isDebugBuild: true
            ) == nil
        )
        #expect(
            AppTelemetryBootstrap.makeProvider(
                infoDictionary: [
                    "LokiKitBlobEndpoint": "$(LOKIKIT_BLOB_ENDPOINT)",
                    "LokiKitBlobSAS": "$(LOKIKIT_BLOB_SAS)"
                ],
                version: "1.1",
                build: "7",
                isDebugBuild: true
            ) == nil
        )
    }
}
