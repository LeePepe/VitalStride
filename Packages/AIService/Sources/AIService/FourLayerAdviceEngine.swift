import Foundation

/// L1-to-L4 synthesis facade. A malformed, unavailable, or failed model response
/// is treated as a normal fallback condition and never leaves advice blank.
public struct FourLayerAdviceEngine: Sendable {
    private let provider: (any AIProvider)?
    private let fallback: DeterministicFourLayerEngine

    public init(provider: (any AIProvider)? = nil, fallback: DeterministicFourLayerEngine = DeterministicFourLayerEngine()) {
        self.provider = provider
        self.fallback = fallback
    }

    public func generate(snapshot: PhysiologicalSnapshot, model: String? = nil) async -> HolisticFourLayerReport {
        guard let provider else { return fallback.makeReport(from: snapshot) }
        do {
            let snapshotData = try JSONEncoder().encode(snapshot)
            guard let snapshotJSON = String(data: snapshotData, encoding: .utf8) else {
                return fallback.makeReport(from: snapshot)
            }
            let response = try await provider.chat(
                messages: [
                    ChatMessage(role: "system", content: "Return only a JSON HolisticFourLayerReport."),
                    ChatMessage(role: "user", content: snapshotJSON),
                ],
                model: model
            )
            guard let reportData = response.content.data(using: .utf8),
                  let report = try? JSONDecoder().decode(HolisticFourLayerReport.self, from: reportData) else {
                return fallback.makeReport(from: snapshot)
            }
            return report
        } catch {
            return fallback.makeReport(from: snapshot)
        }
    }

    public func synthesize(snapshot: PhysiologicalSnapshot, model: String? = nil) async -> HolisticFourLayerReport {
        await generate(snapshot: snapshot, model: model)
    }
}
