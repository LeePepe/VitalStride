import Foundation
import SwiftData
import Testing
@testable import VitalModels

// MY-1387 / Stage6b — 永久态字段白名单红线测试（宪法 I）
//
// 本 suite 是 `RoutingSignalEntry` 与 `BanditArmStateEntry` 的永久态字段清单机械化护栏：
//   - 若有人给这两个 entry 追加新健康数值字段（例如 heartRate、steps、weight），白名单断言 FAIL
//   - 若 Stage 6c-e ship-gate 把 `RoutingSignalEntry` 的 TEMP-PRELAUNCH raw 字段真正移除，
//     本文件的 `nonTempPermanentAttributes(...)` 已排除它们，永久白名单断言仍成立，无需改测试
//
// 依赖：SwiftData 反射 —— `ModelConfiguration.schema.entities` 只暴露 `@Attribute` 持久化字段，
// 所以断言的是「实际会被写盘的字段清单」，比 Mirror(reflecting:) 更贴近红线本意。
@Suite("Routing models persisted-fields redline")
struct RoutingModelsPersistedFieldsRedlineTests {

    // MARK: - White lists (永久态字段，宪法 I)

    /// `BanditArmStateEntry` 永久白名单 —— 该 entry 无 TEMP-PRELAUNCH 例外
    private static let banditPermanentWhitelist: Set<String> = [
        "kind", "deviceTier", "provider", "count", "rewardSum", "updatedAt",
    ]

    /// `RoutingSignalEntry` 永久白名单 —— 不含 TEMP-PRELAUNCH `rawPromptDebug` / `rawResponseDebug`
    /// FR-017 上架前须由 Stage 6e 移除 raw 字段；见 CONTEXT.md red_lines
    private static let routingSignalPermanentWhitelist: Set<String> = [
        "kind", "provider", "deviceTier", "latencyMs", "schemaValid", "accepted", "timestamp",
    ]

    /// TEMP-PRELAUNCH 例外字段，本任务不删，只显式排除
    private static let routingSignalTempPrelaunchExceptions: Set<String> = [
        "rawPromptDebug", "rawResponseDebug",
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

    /// 排除 TEMP-PRELAUNCH 例外后的永久字段集，用于永久白名单比对
    private static func nonTempPermanentAttributes(_ attrs: Set<String>,
                                                   exceptions: Set<String>) -> Set<String> {
        attrs.subtracting(exceptions)
    }

    // MARK: - Tests

    @Test("BanditArmStateEntry 持久化字段 == 永久白名单（多一个少一个都 FAIL）")
    func banditArmStateEntryPersistedFieldsMatchWhitelist() throws {
        let attrs = try Self.attributes(for: "BanditArmStateEntry")
        #expect(attrs == Self.banditPermanentWhitelist,
                "BanditArmStateEntry 永久白名单红线（宪法 I）被打破。期望: \(Self.banditPermanentWhitelist)；实际: \(attrs)")
    }

    @Test("RoutingSignalEntry 永久字段（排除 TEMP-PRELAUNCH）== 永久白名单")
    func routingSignalEntryPermanentFieldsMatchWhitelist() throws {
        let attrs = try Self.attributes(for: "RoutingSignalEntry")
        let permanent = Self.nonTempPermanentAttributes(attrs,
                                                       exceptions: Self.routingSignalTempPrelaunchExceptions)
        #expect(permanent == Self.routingSignalPermanentWhitelist,
                "RoutingSignalEntry 永久白名单红线（宪法 I / FR-017 前置护栏）被打破。期望永久: \(Self.routingSignalPermanentWhitelist)；实际去除 TEMP-PRELAUNCH 例外后: \(permanent)；实际全集: \(attrs)")

        // 注意：不断言 TEMP-PRELAUNCH 字段仍在。这些字段（rawPromptDebug/rawResponseDebug）
        // 由 Stage 6e / FR-017 移除；一旦移除，`nonTempPermanentAttributes(...)` 会得到相同的
        // 永久白名单集合，本测试仍然通过 —— 这是「永久态红线」的正确形状：只锁永久字段清单，
        // 对 TEMP-PRELAUNCH 例外只做集合减法，不做存在性断言。
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
