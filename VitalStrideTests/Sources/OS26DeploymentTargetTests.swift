import Foundation
import Testing

@Suite("OS 26 deployment target contract")
struct OS26DeploymentTargetTests {
    private let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    @Test("project and watch targets declare OS 26")
    func projectTargetsDeclareOS26() throws {
        let project = try contents(of: "project.yml")

        #expect(project.contains("iOS: \"26.0\""))
        #expect(project.contains("macOS: \"26.0\""))
        #expect(project.contains("watchOS: \"26.0\""))
        #expect(project.filterOccurrences(of: "WATCHOS_DEPLOYMENT_TARGET: \"26.0\"") == 2)
    }

    @Test("all local package manifests declare OS 26")
    func packageManifestsDeclareOS26() throws {
        let packagePaths = [
            "Packages/VitalModels/Package.swift",
            "Packages/HealthKitService/Package.swift",
            "Packages/AIService/Package.swift",
            "Packages/VitalUI/Package.swift",
            "Packages/TelemetryKit/Package.swift",
            "Packages/DesignKit/Package.swift",
            "Packages/FlightKit/Package.swift",
        ]

        for path in packagePaths {
            let manifest = try contents(of: path)
            #expect(manifest.contains(".iOS(\"26.0\")"))
            #expect(manifest.contains(".macOS(\"26.0\")"))
            #expect(manifest.contains(".watchOS(\"26.0\")"))
        }
    }

    private func contents(of relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}

private extension String {
    func filterOccurrences(of needle: String) -> Int {
        components(separatedBy: needle).count - 1
    }
}
