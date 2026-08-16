import Foundation
import SwiftData
import Testing
@testable import VitalModels

// MY-1387 / Stage6b — 永久态字段白名单红线测试（宪法 I）
// MY-1390 / Stage6e — ship-gate 收窄：受控临时例外已随 raw 字段一并移除，
// 白名单断言现在直接比对全字段集，不再做集合减法。
//
// 本 suite 是 `RoutingSignalEntry` 与 `BanditArmStateEntry` 的永久态字段清单机械化护栏：
//   - 若有人给这两个 entry 追加新健康数值字段（例如 heartRate、steps、weight），白名单断言 FAIL
//   - 若有人重新引入已被 FR-017 移除的 raw 调试字段，全字段集比对同样 FAIL
//
// 依赖：SwiftData 反射 —— `ModelConfiguration.schema.entities` 只暴露 `@Attribute` 持久化字段，
// 所以断言的是「实际会被写盘的字段清单」，比 Mirror(reflecting:) 更贴近红线本意。
@Suite("Routing models persisted-fields redline")
struct RoutingModelsPersistedFieldsRedlineTests {

    // MARK: - White lists (永久态字段，宪法 I)

    /// `BanditArmStateEntry` 永久白名单
    private static let banditPermanentWhitelist: Set<String> = [
        "kind", "deviceTier", "provider", "count", "rewardSum", "updatedAt",
    ]

    /// `RoutingSignalEntry` 永久白名单 —— FR-017 收窄后的完整持久化字段集（7 个）
    /// 见 CONTEXT.md red_lines
    private static let routingSignalPermanentWhitelist: Set<String> = [
        "kind", "provider", "deviceTier", "latencyMs", "schemaValid", "accepted", "timestamp",
    ]

    // MARK: - Helpers

    private static func attributes(for entityName: String) throws -> Set<String> {
        let container = try ModelContainerConfiguration.makeTestContainer()
        let config = try #require(container.configurations.first {
            ($0.schema?.entities ?? []).contains(where: { $0.name == entityName })
        }, "\(entityName) must be registered in a ModelConfiguration")
        let entity = try #require((config.schema?.entities ?? []).first(where: { $0.name == entityName }),
                                  "Entity \(entityName) missing from configuration schema")
        return Set(entity.attributes.map(\.name))
    }

    // MARK: - Tests

    @Test("BanditArmStateEntry 持久化字段 == 永久白名单（多一个少一个都 FAIL）")
    func banditArmStateEntryPersistedFieldsMatchWhitelist() throws {
        let attrs = try Self.attributes(for: "BanditArmStateEntry")
        #expect(attrs == Self.banditPermanentWhitelist,
                "BanditArmStateEntry 永久白名单红线（宪法 I）被打破。期望: \(Self.banditPermanentWhitelist)；实际: \(attrs)")
    }

    @Test("RoutingSignalEntry 持久化字段 == 永久白名单（多一个少一个都 FAIL）")
    func routingSignalEntryPermanentFieldsMatchWhitelist() throws {
        let attrs = try Self.attributes(for: "RoutingSignalEntry")
        #expect(attrs == Self.routingSignalPermanentWhitelist,
                "RoutingSignalEntry 永久白名单红线（宪法 I / FR-017 永久态）被打破。期望: \(Self.routingSignalPermanentWhitelist)；实际: \(attrs)")
    }

    @Test("BanditArmStateEntry 与 RoutingSignalEntry 均不含任何健康/训练数值字段")
    func bothEntriesContainNoHealthValueFields() throws {
        // 健康/训练数值字段黑名单：宪法 I 禁止 telemetry / bandit 记录任何健康数值
        let forbiddenSubstrings: [String] = [
            "heart", "pulse", "hr", "bp",
            "steps", "distance", "calorie", "energy",
            "glucose", "oxygen", "spo2", "vo2",
            "weight", "reps", "workout", "exercise", "hrv",
            "userId", "user_id",
        ]

        let bandit = try Self.attributes(for: "BanditArmStateEntry")
        let routing = try Self.attributes(for: "RoutingSignalEntry")

        for entry in [("BanditArmStateEntry", bandit), ("RoutingSignalEntry", routing)] {
            let (name, attrs) = entry
            for attr in attrs {
                let lower = attr.lowercased()
                for keyword in forbiddenSubstrings {
                    #expect(!lower.contains(keyword),
                            "\(name).\(attr) 命中健康字段黑名单关键词 '\(keyword)'（宪法 I 永久态红线）")
                }
            }
        }
    }
}
