import Foundation
import Testing
@testable import VitalStride

@Suite("Four-layer summary component contract")
struct FourLayerSummaryComponentsTests {
    @Test("summary component source covers every layer and platform detail action")
    func sourceContract() throws {
        let source = try String(contentsOfFile: sourcePath("VitalStride/Sources/FourLayerSummaryComponents.swift"), encoding: .utf8)
        for symbol in [
            "FourLayerSummaryDashboard",
            "L1HeartAutonomicCard",
            "L1SleepRecoveryCard",
            "L1TrainingLoadCard",
            "L1AerobicCapacityCard",
            "L1DailyNEATCard",
            "L2CrossDomainCouplingSection",
            "L3ReadinessPeriodizationCard",
            "L4NorthStarDirectiveCard",
            "PlatformHealthDetailActionButton",
            "Compact7DayTrendPopover",
            "x-apple-health://"
        ] {
            #expect(source.contains(symbol))
        }
        #expect(!source.contains("displayLimit = 200"))
        #expect(!source.contains("raw_sample_transaction_list"))
        #expect(!source.contains("ForEach(recentPoints)"))
        #expect(!source.contains("@unchecked Sendable"))
        #expect(!source.contains("nonisolated(unsafe)"))
    }

    @Test("preview host uses layer slugs, titles, and snapshot names")
    func previewLayerContract() throws {
        let source = try String(contentsOfFile: sourcePath("Prototype/Sources/Prototype/VitalStridePreviewHostBoard.swift"), encoding: .utf8)
        for value in [
            "vs-l1-atomic-domain-cards",
            "vs-l2-cross-domain-coupling-cards",
            "vs-l3-readiness-periodization-cards",
            "vs-l4-north-star-directive-cards",
            "layer1-atomic-domain-cards-10up.png",
            "layer2-cross-domain-coupling-cards-10up.png",
            "layer3-readiness-periodization-cards-10up.png",
            "layer4-north-star-directive-cards-10up.png",
            "String(format: \"L1-V%02d",
            "String(format: \"L2-V%02d",
            "String(format: \"L3-V%02d",
            "String(format: \"L4-V%02d"
        ] {
            #expect(source.contains(value))
        }
        #expect(source.contains("let code = String(format: \"v%02d\", index + 1)"))
        #expect(source.contains("let badge = String(format: \"L%d-V%02d\", rawValue, index + 1)"))
        #expect(source.contains("keyboardShortcut(KeyEquivalent(tab.shortcutDigit), modifiers: .command)"))
        #expect(source.contains("SELECT"))
        #expect(source.contains("STAR"))
        #expect(source.contains("NOTES"))
    }

    @Test("detail sources are aggregate-only and keep a platform action")
    func detailSourcesStaySubtractive() throws {
        let names = [
            "HeartRateSection.swift",
            "SleepSection.swift",
            "StepsSection.swift",
            "ActiveEnergySection.swift",
            "BodyWeightSection.swift",
            "GenericHealthDetailView.swift"
        ]
        for name in names {
            let source = try String(contentsOfFile: sourcePath("VitalStride/Sources/DataSections/\(name)"), encoding: .utf8)
            #expect(source.contains("PlatformHealthDetailActionButton"))
            #expect(!source.contains("displayLimit = 200"))
            #expect(!source.contains("按日明细"))
            #expect(!source.contains("按夜明细"))
        }
    }

    private func sourcePath(_ relativePath: String) -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .path
    }
}
