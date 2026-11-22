#if canImport(AppKit)
import AppKit
#endif
import DesignKit
import Foundation
@testable import Prototype
import SwiftUI
import Testing

@Suite("VitalStridePreviewHost button hot-path & zero-redraw contract", .serialized)
struct VitalStridePreviewHostPerformanceTests {
    @MainActor
    @Test("SELECT, STAR, and NOTES complete in < 5ms on @MainActor with 0 candidate viewport redraws")
    func selectStarAndNotesStaySub5msWithZeroViewportRedraws() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vs-preview-perf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let page = VitalStridePreviewPageTab.page1HolisticDashboard
        let coordinator = VitalStridePreviewBoardCoordinator(
            initialPage: page,
            handoffRootDirectory: tempDir.path
        )
        let board = VitalStridePreviewHostBoard(coordinator: coordinator)
        let controller = coordinator.controller(for: page)
        let receiptURL = controller.receiptWriter.fileURL

        #if os(macOS)
        PreviewViewportRenderDiagnostics.reset()
        let hosting = NSHostingView(rootView: board)
        hosting.frame = NSRect(x: 0, y: 0, width: 1680, height: 1020)
        hosting.layoutSubtreeIfNeeded()
        let initialViewportEvaluations = PreviewViewportRenderDiagnostics.evaluationCount
        #expect(initialViewportEvaluations == 10)
        for index in 1...10 {
            let vid = String(format: "v%02d", index)
            #expect(
                PreviewViewportRenderDiagnostics.evaluationCount(
                    boardIdentity: page.goalSlug,
                    variantID: vid
                ) == 1
            )
        }
        for inactivePage in VitalStridePreviewPageTab.allCases where inactivePage != page {
            for index in 1...10 {
                let vid = String(format: "v%02d", index)
                #expect(
                    PreviewViewportRenderDiagnostics.evaluationCount(
                        boardIdentity: inactivePage.goalSlug,
                        variantID: vid
                    ) == 0
                )
            }
        }
        #endif

        // Warm up once before sub-5ms microbenchmark to exclude one-time symbol lookup.
        controller.toggleStar(for: "v10")
        controller.toggleStar(for: "v10")
        #if os(macOS)
        hosting.layoutSubtreeIfNeeded()
        let baselineEvaluations = PreviewViewportRenderDiagnostics.evaluationCount
        #expect(baselineEvaluations == initialViewportEvaluations)
        #endif

        let clock = ContinuousClock()
        let burstElapsed = clock.measure {
            for index in 0..<20 {
                let variantID = String(format: "v%02d", (index % 10) + 1)
                controller.toggleStar(for: variantID)
                controller.selectVariant(variantID)
                controller.updateNotes(for: variantID, notes: "流畅无卡顿-\(index)")
            }
        }
        let burstMilliseconds = Double(burstElapsed.components.seconds) * 1_000.0
            + Double(burstElapsed.components.attoseconds) / 1_000_000_000_000_000.0
        #expect(
            burstMilliseconds < 5.0,
            "Expected 20 rapid SELECT/STAR/NOTES mutations on @MainActor in < 5ms, got \(burstMilliseconds)ms"
        )

        #if os(macOS)
        hosting.layoutSubtreeIfNeeded()
        let postBurstEvaluations = PreviewViewportRenderDiagnostics.evaluationCount
        #expect(postBurstEvaluations - baselineEvaluations == 0)
        #endif

        controller.selectVariant(nil)
        for id in (1...10).map({ String(format: "v%02d", $0) }) {
            if controller.starredVariantIDs.contains(id) {
                controller.toggleStar(for: id)
            }
            controller.updateNotes(for: id, notes: "")
        }

        #if os(macOS)
        hosting.layoutSubtreeIfNeeded()
        let preSingleEvaluations = PreviewViewportRenderDiagnostics.evaluationCount
        #expect(preSingleEvaluations == initialViewportEvaluations)
        #endif

        let singlePassElapsed = clock.measure {
            controller.selectVariant("v03")
            controller.toggleStar(for: "v01")
            controller.toggleStar(for: "v02")
            controller.updateNotes(for: "v02", notes: "L1 卡片密度与对比度极佳")
        }
        let singlePassMs = Double(singlePassElapsed.components.seconds) * 1_000.0
            + Double(singlePassElapsed.components.attoseconds) / 1_000_000_000_000_000.0
        #expect(
            singlePassMs < 5.0,
            "Expected single-pass SELECT/STAR/NOTES mutations in < 5ms, got \(singlePassMs)ms"
        )

        #if os(macOS)
        hosting.layoutSubtreeIfNeeded()
        let postSingleEvaluations = PreviewViewportRenderDiagnostics.evaluationCount
        #expect(postSingleEvaluations - preSingleEvaluations == 0)
        #endif

        controller.flush()
        let data = try Data(contentsOf: receiptURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let persisted = try decoder.decode(PreviewSelectionReceipt.self, from: data)
        #expect(persisted.selectedVariantID == "v03")
        #expect(persisted.starredVariantIDs == ["v01", "v02"])
        #expect(persisted.notesByVariant["v02"] == "L1 卡片密度与对比度极佳")
    }

    @MainActor
    @Test("Debounced receipt writer coalesces rapid mutations and flush() persists latest state deterministically")
    func debouncedReceiptWriterCoalescesAndFlushes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vs-receipt-debounce-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let receiptURL = directory.appendingPathComponent("receipts/preview-selection.json")

        let writer = PreviewSelectionReceiptWriter(
            fileURL: receiptURL,
            defaultAppearance: "light",
            debounceInterval: 0.15
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        for idx in 1...10 {
            let vid = String(format: "v%02d", idx)
            _ = try writer.selectVariant(vid, now: now.addingTimeInterval(Double(idx)))
            _ = try writer.toggleStar(for: vid, now: now.addingTimeInterval(Double(idx)))
            _ = try writer.updateNotes(for: vid, notes: "Note \(idx)", now: now.addingTimeInterval(Double(idx)))
        }

        #expect(writer.currentReceipt.selectedVariantID == "v10")
        #expect(writer.currentReceipt.starredVariantIDs.count == 10)
        #expect(writer.currentReceipt.notesByVariant["v10"] == "Note 10")

        // Before 150ms debounce elapses, flush() must synchronously drain the latest coalesced receipt to disk.
        writer.flush()
        #expect(FileManager.default.fileExists(atPath: receiptURL.path))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let flushed = try decoder.decode(PreviewSelectionReceipt.self, from: Data(contentsOf: receiptURL))
        #expect(flushed.selectedVariantID == "v10")
        #expect(flushed.starredVariantIDs.count == 10)
        #expect(flushed.notesByVariant["v10"] == "Note 10")

        let resetResult = try writer.archiveAndResetRound(explicitRound: 1, defaultAppearance: "dark", now: now.addingTimeInterval(100))
        #expect(resetResult.archivedURL?.lastPathComponent == "preview-selection.round-1.json")
        #expect(resetResult.resetReceipt.selectedVariantID == nil)
        #expect(resetResult.resetReceipt.starredVariantIDs.isEmpty)
        #expect(resetResult.resetReceipt.notesByVariant.isEmpty)
        #expect(resetResult.resetReceipt.appearance == "dark")
        writer.flush()
        if let archivedURL = resetResult.archivedURL {
            #expect(FileManager.default.fileExists(atPath: archivedURL.path))
        }
    }
}
