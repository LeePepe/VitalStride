import Foundation
import Testing
@testable import AIService

@Suite("AI Output Structs Tests")
struct AIOutputStructsTests {

    // MARK: - OverviewInsight

    @Test("OverviewInsight JSON roundtrip with all fields")
    func overviewInsightFullRoundtrip() throws {
        let insight = OverviewInsight(
            key: "sleep_warning",
            cardType: "insight",
            cardSize: "medium",
            title: "睡眠不足",
            content: "昨晚只睡了5小时",
            suggestion: "建议今晚早睡",
            iconName: "moon.zzz"
        )

        let data = try JSONEncoder().encode(insight)
        let decoded = try JSONDecoder().decode(OverviewInsight.self, from: data)

        #expect(decoded == insight)
        #expect(decoded.key == "sleep_warning")
        #expect(decoded.cardType == "insight")
        #expect(decoded.cardSize == "medium")
        #expect(decoded.title == "睡眠不足")
        #expect(decoded.content == "昨晚只睡了5小时")
        #expect(decoded.suggestion == "建议今晚早睡")
        #expect(decoded.iconName == "moon.zzz")
    }

    @Test("OverviewInsight JSON roundtrip with nil optionals")
    func overviewInsightNilOptionals() throws {
        let insight = OverviewInsight(
            key: "weight_trend",
            cardType: "trend",
            cardSize: "small",
            title: "体重趋势",
            content: "体重 87.6kg"
        )

        let data = try JSONEncoder().encode(insight)
        let decoded = try JSONDecoder().decode(OverviewInsight.self, from: data)

        #expect(decoded == insight)
        #expect(decoded.suggestion == nil)
        #expect(decoded.iconName == nil)
    }

    @Test("OverviewInsight array JSON roundtrip")
    func overviewInsightArrayRoundtrip() throws {
        let insights = [
            OverviewInsight(key: "a", cardType: "metric", cardSize: "small", title: "T1", content: "C1"),
            OverviewInsight(key: "b", cardType: "summary", cardSize: "large", title: "T2", content: "C2", suggestion: "S2", iconName: "heart"),
        ]

        let data = try JSONEncoder().encode(insights)
        let decoded = try JSONDecoder().decode([OverviewInsight].self, from: data)

        #expect(decoded == insights)
        #expect(decoded.count == 2)
    }

    // MARK: - TrainingRecommendation

    @Test("TrainingRecommendation JSON roundtrip")
    func trainingRecommendationRoundtrip() throws {
        let recommendation = TrainingRecommendation(
            title: "今日推荐：上肢拉",
            muscleGroups: ["back", "arms"],
            exercises: ["引体向上", "杠铃划船", "二头弯举"],
            reasoning: "连续两天推类训练，今天建议拉类动作"
        )

        let data = try JSONEncoder().encode(recommendation)
        let decoded = try JSONDecoder().decode(TrainingRecommendation.self, from: data)

        #expect(decoded == recommendation)
        #expect(decoded.muscleGroups.count == 2)
        #expect(decoded.exercises.count == 3)
    }

    @Test("TrainingRecommendation with empty arrays")
    func trainingRecommendationEmptyArrays() throws {
        let recommendation = TrainingRecommendation(
            title: "休息日",
            muscleGroups: [],
            exercises: [],
            reasoning: "连续训练4天，建议休息"
        )

        let data = try JSONEncoder().encode(recommendation)
        let decoded = try JSONDecoder().decode(TrainingRecommendation.self, from: data)

        #expect(decoded == recommendation)
        #expect(decoded.muscleGroups.isEmpty)
        #expect(decoded.exercises.isEmpty)
    }

    // MARK: - DataAnalysis

    @Test("DataAnalysis JSON roundtrip with all fields")
    func dataAnalysisFullRoundtrip() throws {
        let analysis = DataAnalysis(
            sampleType: "bodyMass",
            summary: "过去7天体重从88kg降至87kg",
            trend: "falling",
            suggestion: "保持当前饮食计划"
        )

        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(DataAnalysis.self, from: data)

        #expect(decoded == analysis)
        #expect(decoded.sampleType == "bodyMass")
        #expect(decoded.trend == "falling")
        #expect(decoded.suggestion == "保持当前饮食计划")
    }

    @Test("DataAnalysis JSON roundtrip with nil suggestion")
    func dataAnalysisNilSuggestion() throws {
        let analysis = DataAnalysis(
            sampleType: "heartRate",
            summary: "心率数据不足",
            trend: "insufficient"
        )

        let data = try JSONEncoder().encode(analysis)
        let decoded = try JSONDecoder().decode(DataAnalysis.self, from: data)

        #expect(decoded == analysis)
        #expect(decoded.suggestion == nil)
    }

    @Test("DataAnalysis all trend values")
    func dataAnalysisAllTrends() throws {
        let trends = ["rising", "falling", "stable", "insufficient"]
        for trend in trends {
            let analysis = DataAnalysis(
                sampleType: "stepCount",
                summary: "test",
                trend: trend
            )
            let data = try JSONEncoder().encode(analysis)
            let decoded = try JSONDecoder().decode(DataAnalysis.self, from: data)
            #expect(decoded.trend == trend)
        }
    }

    // MARK: - AIAnalysisResponse

    @Test("AIAnalysisResponse decodes headline with insights")
    func aiAnalysisResponseWithHeadline() throws {
        let json = """
        {
            "headline": "睡眠比上周提升12%",
            "insights": [
                {
                    "key": "sleep_improve",
                    "cardType": "insight",
                    "cardSize": "medium",
                    "title": "睡眠改善",
                    "content": "本周平均睡眠7.5小时"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AIAnalysisResponse.self, from: json)

        #expect(decoded.headline == "睡眠比上周提升12%")
        #expect(decoded.insights.count == 1)
        #expect(decoded.insights[0].key == "sleep_improve")
        #expect(decoded.insights[0].title == "睡眠改善")
    }

    @Test("AIAnalysisResponse decodes null headline")
    func aiAnalysisResponseNullHeadline() throws {
        let json = """
        {
            "headline": null,
            "insights": [
                {
                    "key": "weight_trend",
                    "cardType": "trend",
                    "cardSize": "small",
                    "title": "体重趋势",
                    "content": "体重稳定在87kg"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AIAnalysisResponse.self, from: json)

        #expect(decoded.headline == nil)
        #expect(decoded.insights.count == 1)
    }

    @Test("AIAnalysisResponse decodes missing headline key")
    func aiAnalysisResponseMissingHeadline() throws {
        let json = """
        {
            "insights": [
                {
                    "key": "hr",
                    "cardType": "metric",
                    "cardSize": "small",
                    "title": "心率",
                    "content": "静息心率62bpm"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AIAnalysisResponse.self, from: json)

        #expect(decoded.headline == nil)
        #expect(decoded.insights.count == 1)
    }

    @Test("AIAnalysisResponse roundtrip preserves equality")
    func aiAnalysisResponseRoundtrip() throws {
        let response = AIAnalysisResponse(
            headline: "步数创新高",
            insights: [
                OverviewInsight(key: "steps", cardType: "metric", cardSize: "large", title: "步数", content: "今日15000步", suggestion: "继续保持", iconName: "figure.walk"),
                OverviewInsight(key: "cal", cardType: "metric", cardSize: "small", title: "热量", content: "消耗800大卡"),
            ]
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(AIAnalysisResponse.self, from: data)

        #expect(decoded == response)
        #expect(decoded.insights.count == 2)
    }

    @Test("AIAnalysisResponse with empty insights array")
    func aiAnalysisResponseEmptyInsights() throws {
        let json = """
        {"headline": "无变化", "insights": []}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AIAnalysisResponse.self, from: json)

        #expect(decoded.headline == "无变化")
        #expect(decoded.insights.isEmpty)
    }

    // MARK: - Cross-type JSON

    @Test("Different output types produce distinct JSON")
    func distinctJSONKeys() throws {
        let insightData = try JSONEncoder().encode(
            OverviewInsight(key: "k", cardType: "t", cardSize: "s", title: "t", content: "c")
        )
        let recommendationData = try JSONEncoder().encode(
            TrainingRecommendation(title: "t", muscleGroups: [], exercises: [], reasoning: "r")
        )
        let analysisData = try JSONEncoder().encode(
            DataAnalysis(sampleType: "s", summary: "s", trend: "stable")
        )

        let insightJSON = try JSONSerialization.jsonObject(with: insightData) as! [String: Any]
        let recommendationJSON = try JSONSerialization.jsonObject(with: recommendationData) as! [String: Any]
        let analysisJSON = try JSONSerialization.jsonObject(with: analysisData) as! [String: Any]

        #expect(insightJSON.keys.contains("cardType"))
        #expect(recommendationJSON.keys.contains("muscleGroups"))
        #expect(analysisJSON.keys.contains("sampleType"))
    }
}
