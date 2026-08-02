import Foundation
import Testing
@testable import AIService

@Suite("AIRoutingEvaluator")
struct AIRoutingEvaluationsTests {

    @Test("HeuristicAIRoutingGrader scores empty response as 0")
    func heuristicScoresEmptyAsZero() async throws {
        let sample = AIRoutingEvaluationSample(
            kind: .substitute,
            mainProvider: "apple_intelligence",
            candidateProvider: "zhipu",
            mainResponse: "",
            candidateResponse: "some non-empty reply"
        )
        let scores = await AIRoutingEvaluator.evaluate(samples: [sample])
        let score = try #require(scores.first)
        #expect(score.mainScore == 0)
        #expect(score.candidateScore != nil)
        #expect((score.candidateScore ?? 0) > 0)
    }

    @Test("evaluate produces one score per sample, in input order")
    func evaluatePreservesOrderAndCount() async {
        let samples: [AIRoutingEvaluationSample] = [
            .init(kind: .chat, mainProvider: "a", candidateProvider: "b",
                  mainResponse: "one", candidateResponse: "two"),
            .init(kind: .substitute, mainProvider: "a", candidateProvider: "b",
                  mainResponse: "three three three", candidateResponse: "four"),
        ]
        let scores = await AIRoutingEvaluator.evaluate(samples: samples)
        #expect(scores.count == 2)
        // Deterministic heuristic: longer main string → higher main score in
        // the second sample than in the first.
        #expect((scores[1].mainScore ?? 0) > (scores[0].mainScore ?? 0))
    }

    @Test("FR-011: evaluator does not require Apple Evaluations to be available")
    func evaluatorRunsRegardlessOfPlatform() async {
        // The dataset MUST be evaluable on any supported SDK — Evaluations may
        // or may not be present. If Apple's framework is unavailable, the
        // pipeline SHOULD skip (return nil) rather than fail. Default grader
        // is the heuristic so a score always comes back, guaranteeing the
        // plumbing is exercised in CI.
        let scores = await AIRoutingEvaluator.evaluate(samples: [
            .init(kind: .chat, mainProvider: "m", candidateProvider: "c",
                  mainResponse: "hi", candidateResponse: "hi")
        ])
        #expect(scores.count == 1)
    }

    @Test("isAppleEvaluationsAvailable is a plain Bool (never traps)")
    func availabilityFlagReadable() {
        // Just reading it MUST NOT trap under any SDK / OS combination.
        _ = AIRoutingEvaluator.isAppleEvaluationsAvailable
    }

    // MARK: - Static assertion: not used at runtime

    @Test("FR-011: AIRouter.execute does not depend on evaluator / grader types")
    func routerHasNoRuntimeDependencyOnEvaluations() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AIService")

        let routerURL = root.appendingPathComponent("AIRouter.swift")
        let routerSource = try String(contentsOf: routerURL, encoding: .utf8)

        // Strip comments so we scan CODE only.
        let codeOnly = routerSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") {
                    return ""
                }
                return line
            }
            .joined(separator: "\n")

        for token in [
            "AIRoutingEvaluator",
            "AIRoutingGrader",
            "AppleEvaluationsGrader",
            "HeuristicAIRoutingGrader",
        ] {
            #expect(!codeOnly.contains(token),
                    "AIRouter.swift references \(token) — evaluations must remain offline-only (FR-011)")
        }
    }
}
