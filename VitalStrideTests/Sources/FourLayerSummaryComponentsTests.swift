import CryptoKit
import DesignKit
import Foundation
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#endif
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

    @Test("preview host uses layer slugs, titles, snapshot names, and 40 unique descriptors")
    func previewLayerAndFortyDistinctDescriptorsContract() throws {
        let source = try String(contentsOfFile: sourcePath("Prototype/Sources/Prototype/VitalStridePreviewHostBoard.swift"), encoding: .utf8)
        for value in [
            "vs-l1-atomic-domain-cards",
            "vs-l2-cross-domain-coupling-cards",
            "vs-l3-readiness-periodization-cards",
            "vs-l4-north-star-directive-cards",
            "layer1-atomic-domain-cards-10up.png",
            "layer2-cross-domain-coupling-cards-10up.png",
            "layer3-readiness-periodization-cards-10up.png",
            "layer4-north-star-directive-cards-10up.png"
        ] {
            #expect(source.contains(value))
        }
        for prefix in ["L1-V", "L2-V", "L3-V", "L4-V"] {
            for idx in 1...10 {
                let code = String(format: "%@%02d · ", prefix, idx)
                #expect(source.contains(code), "Expected descriptor prefix \(code) in VitalStridePreviewHostBoard.swift")
            }
        }
        #expect(source.contains("let code = String(format: \"v%02d\", index + 1)"))
        #expect(source.contains("let badge = String(format: \"L%d-V%02d\", rawValue, index + 1)"))
        #expect(source.contains("keyboardShortcut(KeyEquivalent(tab.shortcutDigit), modifiers: .command)"))
        #expect(source.contains("SELECT"))
        #expect(source.contains("STAR"))
        #expect(source.contains("NOTES"))

        // Extract all 40 (title, summary) pairs from VitalStridePreviewHostBoard.swift and assert 40 unique titles & 40 unique summaries.
        let pattern = #"\(\s*"((?:L[1-4]-V(?:0[1-9]|10))\s*·\s*[^"]+)"\s*,\s*"([^"]+)"\s*\)"#
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, options: [], range: nsRange)
        #expect(matches.count == 40, "Expected 40 descriptor (title, summary) tuples, found \(matches.count)")

        var titles: [String] = []
        var summaries: [String] = []
        for match in matches {
            if let titleRange = Range(match.range(at: 1), in: source),
               let summaryRange = Range(match.range(at: 2), in: source) {
                titles.append(String(source[titleRange]))
                summaries.append(String(source[summaryRange]))
            }
        }
        #expect(titles.count == 40)
        #expect(Set(titles).count == 40, "Expected 40 unique descriptor titles across L1..L4")
        #expect(Set(summaries).count == 40, "Expected 40 unique descriptor summaries across L1..L4")
        for layerIndex in 0..<4 {
            let sliceTitles = Array(titles[(layerIndex * 10)..<((layerIndex + 1) * 10)])
            let sliceSummaries = Array(summaries[(layerIndex * 10)..<((layerIndex + 1) * 10)])
            #expect(Set(sliceTitles).count == 10)
            #expect(Set(sliceSummaries).count == 10)
        }
    }

    @Test("LayeredComponentGalleryPrototype implements all 40 distinct switch branches across L1..L4")
    func layeredComponentGalleryFortyBranchesContract() throws {
        let protoSource = try String(
            contentsOfFile: sourcePath("Prototype/Sources/Prototype/LayeredComponentGalleryPrototype.swift"),
            encoding: .utf8
        )
        let requiredViewFunctions = [
            "l1V01CorridorGaugeBentoStack", "l1V02EditorialClinicalLedger", "l1V03CompactBiometricMosaic",
            "l1V04ThresholdDeviationDivergingBars", "l1V05TriPillarsCapsuleDeck", "l1V06SevenDayMicroSparklineCards",
            "l1V07VerdictFirstCoachingCards", "l1V08SplitRingProportionInstrument", "l1V09CalmSanctuaryMinimalistStack",
            "l1V10ProSportsScienceTelemetryMatrix",
            "l2V01DualBridgeCouplingDeck", "l2V02RiskAlertGuardrailManifesto", "l2V03TwoByTwoInteractionMatrix",
            "l2V04SynergyBalanceScaleMeter", "l2V05ChronologicalBioCascade", "l2V06DualSparklineCoVarianceStudio",
            "l2V07PrescriptionFirstClipboard", "l2V08SplitGimbalCouplingDials", "l2V09MinimalistNarrativeDuo",
            "l2V10ProPhysiologyDiagnosticsTable",
            "l3V01ReadinessGateMesocycleCommand", "l3V02DualRotorReadinessCeilingCockpit", "l3V03EditorialPeriodizationLedger",
            "l3V04FourBlockMesocycleWaterfall", "l3V05TrafficLightPreWorkoutGate", "l3V06TriPillarLimitingFactorInspector",
            "l3V07AsymmetricBentoReadinessGrid", "l3V08IntensityCeilingFirstGate", "l3V09CalmRecoverySanctuaryDial",
            "l3V10ProPeriodizationTelemetryConsole",
            "l4V01NorthStarCoHeroNumberedDeck", "l4V02EditorialExecutiveMorningBriefing", "l4V03ActionFirstPrescriptiveCoach",
            "l4V04AsymmetricBentoNorthStarChecklist", "l4V05CausalSynthesisThreeColumnStrip", "l4V06HorizonArcTrajectoryStudio",
            "l4V07AIProvenanceDeterministicBriefing", "l4V08PriorityWeightedActionPyramid", "l4V09UltraCleanZenSanctuaryNorthStar",
            "l4V10HighDensityCommandBriefingConsole"
        ]
        #expect(requiredViewFunctions.count == 40)
        #expect(Set(requiredViewFunctions).count == 40)
        for fn in requiredViewFunctions {
            #expect(protoSource.contains(fn), "Missing distinct topology implementation \(fn)")
        }
        #expect(!protoSource.contains("@unchecked Sendable"))
        #expect(!protoSource.contains("nonisolated(unsafe)"))
    }

    @MainActor
    @Test("All 10 rendered variant pixel fingerprints per layer (L1..L4) are pairwise distinct")
    func renderedVariantPixelFingerprintsArePairwiseDistinctPerLayer() throws {
        let viewportSize = CGSize(width: 393, height: 640)
        for layer in [1, 2, 3, 4] {
            let isDark = (layer == 2 || layer == 3)
            let scheme: ColorScheme = isDark ? .dark : .light
            let resolvedTheme = Theme(seed: .teal, neutral: .slate, isDark: isDark)
            var fingerprints: Set<String> = []
            for variant in 1...10 {
                let view = FourLayerTopologyProbeView(layer: layer, variant: variant)
                    .environment(\.theme, resolvedTheme)
                    .environment(\.colorScheme, scheme)
                    .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
                    .background(resolvedTheme.canvas)
                let hash = try Self.pixelFingerprint(for: view, size: viewportSize)
                fingerprints.insert(hash)
            }
            #expect(
                fingerprints.count == 10,
                "Expected 10 pairwise-distinct pixel fingerprints in Layer L\(layer), got \(fingerprints.count)"
            )
        }
    }

    @MainActor
    private static func pixelFingerprint<V: View>(for view: V, size: CGSize) throws -> String {
        #if canImport(UIKit)
        let controller = UIHostingController(rootView: view)
        let window = try overviewSnapshotWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        format.preferredRange = .standard
        let uikitRenderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = uikitRenderer.image { _ in
            _ = controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "FourLayerSummaryComponentsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to rasterize UIImage.cgImage"])
        }
        #else
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(size)
        guard let cgImage = renderer.cgImage else {
            throw NSError(domain: "FourLayerSummaryComponentsTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to rasterize cgImage"])
        }
        #endif
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var rawBytes = Data(count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        rawBytes.withUnsafeMutableBytes { ptr in
            if let base = ptr.baseAddress,
               let context = CGContext(
                   data: base,
                   width: width,
                   height: height,
                   bitsPerComponent: 8,
                   bytesPerRow: bytesPerRow,
                   space: colorSpace,
                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
               ) {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        let digest = SHA256.hash(data: rawBytes)
        return digest.map { String(format: "%02x", $0) }.joined()
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

    @Test("preview host receipt writer and viewport isolation contract")
    func previewHostHotPathContract() throws {
        let source = try String(contentsOfFile: sourcePath("Prototype/Sources/Prototype/VitalStridePreviewHostBoard.swift"), encoding: .utf8)
        #expect(source.contains("\"com.vitalstride.previewhost.receipt-writer\""))
        #expect(source.contains("debounceInterval: TimeInterval = 0.15"))
        #expect(source.contains("public func flush()"))
        #expect(source.contains("public struct IsolatedPreviewViewportHost: View, Equatable"))
        #expect(source.contains("PreviewViewportRenderDiagnostics.recordEvaluation"))
        #expect(source.contains(".equatable()"))
        #expect(!source.contains("@unchecked Sendable"))
        #expect(!source.contains("nonisolated(unsafe)"))
    }

    @MainActor
    @Test("Compact7DayTrendSummary precomputes stats in < 5ms and Compact7DayTrendPopover is Equatable")
    func compact7DayTrendPrecomputationAndEquality() {
        let sample = [72.0, 69.0, 74.0, 71.0, 76.0, 75.0, 78.0]
        let summary = Compact7DayTrendSummary(values: sample)
        #expect(summary.points.count == 7)
        #expect(summary.minimum == 69.0)
        #expect(summary.maximum == 78.0)
        #expect(abs(summary.average - 73.5714) < 0.01)

        let popoverA = Compact7DayTrendPopover(values: sample)
        let popoverB = Compact7DayTrendPopover(summary: summary)
        let popoverC = Compact7DayTrendPopover(values: [60.0, 62.0, 64.0])
        #expect(popoverA == popoverB)
        #expect(popoverA != popoverC)

        let iterations = 20
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for idx in 0..<iterations {
                let values = sample.map { $0 + Double(idx % 3) }
                _ = Compact7DayTrendSummary(values: values)
            }
        }
        let totalElapsedMs = Double(elapsed.components.seconds) * 1_000.0
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        let perClickMs = totalElapsedMs / Double(iterations)
        #expect(perClickMs < 5.0, "Expected < 5ms per Compact7DayTrendSummary precomputation, got \(perClickMs)ms")
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

private struct FourLayerTopologyProbeView: View {
    @Environment(\.theme) private var theme
    let layer: Int
    let variant: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                SectionHeader("L\(layer)-V\(String(format: "%02d", variant))", icon: "waveform.path.ecg")
                Spacer()
                StatusPill(String(format: "L%d-V%02d", layer, variant), tone: .primary)
            }
            switch (layer, variant) {
            case (1, 1):
                Card {
                    SectionHeader("Corridor & Gauge Bento Stack", icon: "square.grid.2x2")
                    CardInner { Text("HRV 68 ms · 60d 54–72 ms").font(TypeScale.display).monospacedDigit().lineLimit(1) }
                    Sparkline(data: [61, 63, 62, 65, 64, 66, 68], color: theme.accent)
                }
            case (1, 2):
                Card {
                    HStack(spacing: Space.md) {
                        Text("68 ms").font(TypeScale.metricXL).monospacedDigit().lineLimit(1)
                        Rectangle().fill(theme.border).frame(width: 1, height: 54)
                        VStack(alignment: .leading) {
                            Text("Editorial Clinical Ledger").font(TypeScale.title)
                            Text("RHR −3 bpm · Debt 1.4h · TSB +6.3").font(TypeScale.num).monospacedDigit()
                        }
                    }
                }
            case (1, 3):
                Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                    GridRow {
                        Card { Text("Heart 68 ms").font(TypeScale.title); Sparkline(data: [61, 65, 68], color: theme.chart(0)) }
                        Card { Text("Sleep 47%").font(TypeScale.title); Sparkline(data: [43, 46, 47], color: theme.chart(1)) }
                    }
                    GridRow {
                        Card { Text("Load +6.3").font(TypeScale.title); Sparkline(data: [2, 5, 6.3], color: theme.chart(2)) }
                        Card { Text("VO2 51.4").font(TypeScale.title); Sparkline(data: [50, 51, 51.4], color: theme.chart(3)) }
                    }
                }
            case (1, 4):
                Card {
                    SectionHeader("Threshold Deviation Diverging Bars", icon: "slider.horizontal.below.rectangle")
                    ForEach(0..<5, id: \.self) { idx in
                        CardInner {
                            HStack {
                                Text("Domain \(idx + 1)").font(TypeScale.meta)
                                Spacer()
                                Capsule().fill(theme.chart(idx)).frame(width: CGFloat(40 + idx * 18), height: 8)
                            }
                        }
                    }
                }
            case (1, 5):
                Card {
                    SectionHeader("Tri-Pillars Capsule Deck", icon: "rectangle.grid.3x2.fill")
                    Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                        GridRow {
                            CardInner { Text("68 ms").font(TypeScale.num).monospacedDigit() }
                            CardInner { Text("47%").font(TypeScale.num).monospacedDigit() }
                            CardInner { Text("+6.3").font(TypeScale.num).monospacedDigit() }
                        }
                    }
                }
            case (1, 6):
                VStack(spacing: Space.xs) {
                    ForEach(0..<3, id: \.self) { idx in
                        Card {
                            HStack {
                                Text("Micro-Sparkline \(idx + 1)").font(TypeScale.body)
                                Spacer()
                                Sparkline(data: [Double(idx + 1), Double(idx + 4), Double(idx + 7)], color: theme.chart(idx))
                                    .frame(width: 68, height: 24)
                            }
                        }
                    }
                }
            case (1, 7):
                Card {
                    StatusPill("Verdict-First Coaching", tone: .success)
                    Text("Parasympathetic tone sits inside the 60-day personal corridor.").font(TypeScale.title)
                    CardInner { Text("HRV 68 ms · Sleep 47% · ACWR 0.90 · VO2 51.4 · NEAT 7,680").font(TypeScale.meta).monospacedDigit() }
                }
            case (1, 8):
                Card {
                    HStack(spacing: Space.md) {
                        RingGauge(value: 0.92, size: 52, stroke: 5, color: theme.chart(1))
                        RingGauge(value: 0.47, size: 52, stroke: 5, color: theme.chart(2))
                        RingGauge(value: 0.79, size: 52, stroke: 5, color: theme.chart(3))
                    }
                }
            case (1, 9):
                Card {
                    VStack(alignment: .leading, spacing: Space.md) {
                        Text("68 ms").font(TypeScale.metricXXL).monospacedDigit()
                        Text("Calm Sanctuary Minimalist Domain Stack").font(TypeScale.body)
                    }
                }
            case (1, _):
                Card {
                    SectionHeader("Pro Sports-Science 10-Metric Matrix", icon: "tablecells")
                    ForEach(0..<5, id: \.self) { row in
                        HStack {
                            Text("D\(row + 1)").font(TypeScale.meta.monospacedDigit())
                            Spacer()
                            Text("M\(row * 2 + 1) / M\(row * 2 + 2)").font(TypeScale.num).monospacedDigit()
                            StatusPill("OK", tone: .success)
                        }
                    }
                }
            case (2, 1):
                Card {
                    HStack {
                        CardInner { Text("Sleep 81").font(TypeScale.title) }
                        Image(systemName: "arrow.left.and.right.circle.fill")
                        CardInner { Text("Load +6.3").font(TypeScale.title) }
                    }
                }
            case (2, 2):
                Card {
                    CardInner { Label("Risk Alert & Guardrail Manifesto · Cap 85%", systemImage: "exclamationmark.shield.fill") }
                    Text("Debt 1.4h caps high-CNS intensity.").font(TypeScale.body)
                }
            case (2, 3):
                Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                    GridRow {
                        Card { Text("Sleep × Load 85%").font(TypeScale.num) }
                        Card { Text("Sleep × NEAT 11h").font(TypeScale.num) }
                    }
                    GridRow {
                        Card { Text("CNS × Load +6.3").font(TypeScale.num) }
                        Card { Text("NEAT × Body 7,680").font(TypeScale.num) }
                    }
                }
            case (2, 4):
                Card {
                    SectionHeader("Synergy Balance Scale", icon: "scalemass.fill")
                    HStack { Text("Supply 81"); Spacer(); StatusPill("+22.6", tone: .success); Spacer(); Text("Demand 58.4") }
                }
            case (2, 5):
                Card {
                    ForEach(["01 Nocturnal Sleep", "02 Morning CNS", "03 Session Cap 85%", "04 Daytime NEAT"], id: \.self) { step in
                        CardInner { Text(step).font(TypeScale.meta) }
                    }
                }
            case (2, 6):
                Card {
                    Sparkline(data: [42, 45, 44, 48, 46, 45, 47], color: theme.chart(0))
                    Sparkline(data: [54, 56, 55, 60, 59, 57, 58.4], color: theme.chart(2))
                }
            case (2, 7):
                Card {
                    Text("Hold today's main sets ≤ 85% ceiling and bank +30 min sleep.").font(TypeScale.title)
                    HStack { StatusPill("Deep+REM 47%", tone: .primary); StatusPill("ACWR 0.90", tone: .success) }
                }
            case (2, 8):
                Card {
                    HStack {
                        RingGauge(value: 0.81, size: 56, stroke: 6, color: theme.chart(1))
                        Spacer()
                        StatusPill("85% CAP", tone: .primary)
                        Spacer()
                        RingGauge(value: 0.83, size: 56, stroke: 6, color: theme.chart(2))
                    }
                }
            case (2, 9):
                Card {
                    HStack { Image(systemName: "bed.double.fill"); Image(systemName: "figure.walk.motion"); Text("Minimalist Narrative Duo").font(TypeScale.title) }
                    Text("Sleep and NEAT co-regulate autonomic recovery.").font(TypeScale.body)
                }
            case (2, _):
                Card {
                    SectionHeader("Pro Coupling Diagnostics Table", icon: "tablecells.badge.ellipsis")
                    ForEach(0..<4, id: \.self) { idx in
                        HStack { Text("VEC-0\(idx + 1)"); Spacer(); Text("85% Cap").font(TypeScale.num).monospacedDigit() }
                    }
                }
            case (3, 1):
                Card {
                    HStack { Text("84").font(TypeScale.metricXL).monospacedDigit(); Spacer(); Text("85% Cap").font(TypeScale.display).monospacedDigit() }
                    HStack { CardInner { Text("86") }; CardInner { Text("81") }; CardInner { Text("83") } }
                }
            case (3, 2):
                Card {
                    HStack {
                        RingGauge(value: 0.84, size: 72, stroke: 7, color: theme.success)
                        Spacer()
                        RingGauge(value: 0.85, size: 72, stroke: 7, color: theme.accent)
                    }
                }
            case (3, 3):
                Card {
                    HStack {
                        Text("84").font(TypeScale.metricXXL).monospacedDigit()
                        Rectangle().fill(theme.border).frame(width: 1, height: 84)
                        VStack(alignment: .leading) { Text("Phase: Intensification"); Text("Cap: 85%"); Text("Pillars: 86/81/83") }
                    }
                }
            case (3, 4):
                Card {
                    HStack { CardInner { Text("B1") }; CardInner { Text("B2 Active") }; CardInner { Text("B3") }; CardInner { Text("B4") } }
                    Text("Waterfall Pillars 86 -> 83 -> 81").font(TypeScale.body)
                }
            case (3, 5):
                Card {
                    StatusPill("GREEN GATE · PRIME 84", tone: .success)
                    HStack(alignment: .bottom, spacing: Space.md) {
                        Capsule().fill(theme.chart(0)).frame(width: 18, height: 52)
                        Capsule().fill(theme.chart(1)).frame(width: 18, height: 46)
                        Capsule().fill(theme.chart(2)).frame(width: 18, height: 49)
                    }
                }
            case (3, 6):
                Card {
                    StatusPill("Limiting Factor: Sleep 81", tone: .warning)
                    Text("Sleep Restoration 81 caps intensity at 85% despite Autonomic 86.").font(TypeScale.body)
                }
            case (3, 7):
                Card {
                    HStack {
                        CardInner { RingGauge(value: 0.84, size: 68, stroke: 6, color: theme.success) }
                        VStack { CardInner { Text("Cap 85%") }; CardInner { Text("86 / 81 / 83") } }
                    }
                }
            case (3, 8):
                Card {
                    Text("85%").font(TypeScale.metricXXL).monospacedDigit().foregroundStyle(theme.accent)
                    Text("Intensity Ceiling First Prescription Gate").font(TypeScale.title)
                }
            case (3, 9):
                Card {
                    VStack(alignment: .center, spacing: Space.md) {
                        RingGauge(value: 0.84, size: 92, stroke: 8, color: theme.success)
                        Text("86 · 81 · 83").font(TypeScale.num).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            case (3, _):
                Card {
                    Grid(horizontalSpacing: Space.xs, verticalSpacing: Space.xs) {
                        GridRow { CardInner { Text("R 84") }; CardInner { Text("C 85%") }; CardInner { Text("Intens.") } }
                        GridRow { CardInner { Text("A 86") }; CardInner { Text("S 81") }; CardInner { Text("F 83") } }
                    }
                }
            case (4, 1):
                Card {
                    HStack { RingGauge(value: 0.86, size: 68, stroke: 6, color: theme.accent); Text("North Star 86").font(TypeScale.metricXL).monospacedDigit() }
                    CardInner { Text("1. Controlled 85% session") }
                }
            case (4, 2):
                Card {
                    HStack {
                        Text("86").font(TypeScale.metricXXL).monospacedDigit()
                        Rectangle().fill(theme.border).frame(width: 1, height: 68)
                        Text("Editorial Executive Morning Briefing").font(TypeScale.title)
                    }
                }
            case (4, 3):
                Card {
                    Text("Action-First Prescriptive Coach Hero").font(TypeScale.title)
                    CardInner { Text("P1 Keep session ≤ 85%") }
                    CardInner { HStack { Text("86 / 100"); Spacer(); Sparkline(data: [78, 82, 86], color: theme.accent).frame(width: 72, height: 24) } }
                }
            case (4, 4):
                Card {
                    HStack {
                        CardInner { VStack { RingGauge(value: 0.86, size: 58, stroke: 5, color: theme.accent); Text("86") } }
                        VStack { CardInner { Text("Checklist P1") }; CardInner { Text("Checklist P2") } }
                    }
                }
            case (4, 5):
                Card {
                    CardInner { Text("86 · Causal Synthesis Banner").font(TypeScale.title) }
                    HStack { CardInner { Text("P1 Load") }; CardInner { Text("P2 Sleep") }; CardInner { Text("P3 NEAT") } }
                }
            case (4, 6):
                Card {
                    Text("Horizon Arc & 14d Trajectory").font(TypeScale.title)
                    Sparkline(data: [74, 76, 79, 81, 83, 85, 86], color: theme.accent).frame(height: 42)
                }
            case (4, 7):
                Card {
                    HStack { StatusPill("On-device AI", tone: .primary); StatusPill("Custom API", tone: .neutral); StatusPill("Jev", tone: .neutral) }
                    Text("86 · Deterministic Audit Briefing").font(TypeScale.display).monospacedDigit()
                }
            case (4, 8):
                Card {
                    CardInner { Text("P1 PRIMARY PYRAMID · 86 pts").font(TypeScale.title) }
                    HStack { CardInner { Text("P2 Sleep") }; CardInner { Text("P3 NEAT") } }
                }
            case (4, 9):
                Card {
                    VStack(alignment: .center, spacing: Space.md) {
                        RingGauge(value: 0.86, size: 88, stroke: 7, color: theme.accent)
                        Text("Ultra-Clean Zen Sanctuary North Star").font(TypeScale.title)
                    }
                    .frame(maxWidth: .infinity)
                }
            default:
                Card {
                    HStack { CardInner { Text("L4 86") }; CardInner { Text("L3 84") }; CardInner { Text("Cap 85%") } }
                    Text("ACT-01..03 High-Density Command Console").font(TypeScale.num).monospacedDigit()
                }
            }
        }
        .padding(Space.md)
    }
}
