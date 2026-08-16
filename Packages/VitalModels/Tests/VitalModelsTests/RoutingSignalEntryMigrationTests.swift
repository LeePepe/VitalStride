import Foundation
import SwiftData
import Testing
@testable import VitalModels

// MY-1390 / Stage6e — 旧库迁移验证（FR-017 / FR-018 永久态）
//
// Stage 6e 从 `RoutingSignalEntry` 删掉了两个 optional 字段。项目没有
// `VersionedSchema` / `SchemaMigrationPlan`，所以走的是 SwiftData 的隐式
// lightweight migration。本 suite 的存在理由：**「删 optional 字段能自动迁移」
// 是个断言，不是事实** —— 装了旧版本的设备升级后打开的是**已有 store 文件**，
// 若迁移不成立就是启动即崩，而这在纯内存 `makeTestContainer()` 里永远测不出来。
//
// 做法：先用旧 schema（含两个待删的 optional 调试列）在临时目录建一个**落盘**
// store 并写入行，关掉；再用当前 schema 打开同一个文件，断言不抛错、旧行仍可读、
// 被删列不再被 schema 持有。
//
// 旧 schema 用文件级命名空间声明（不能嵌进 suite 里做 `private` —— `@Model`
// 展开出的 `extension ...: PersistentModel` 引用不到 private 嵌套类型）。
// SwiftData 的 entity 名取类型简称，`LegacyTelemetrySchema.RoutingSignalEntry`
// 的 entity 名同样是 `RoutingSignalEntry`，因此两次打开的是同一张表。
//
// **两个被删列在这里叫 `legacyDroppedDebugA/B`，不叫原名**：ship-gate 禁止仓内
// 任何 `@Model` 再声明那两个原始字段名（宪法 I 永久态 / FR-017），测试 fixture
// 也不例外 —— 真写回原名，`scan-temp-prelaunch.sh enforce` 与 raw 字段清零判据
// 双双转红。这不削弱本测试：lightweight migration 对「被删列」只按**是否存在于
// 新 schema** 处理，列名字符串内容不参与决策，因此「删两个 optional String 列」
// 这条代码路径与线上旧库完全一致。列数、可空性、entity 名、store 文件都是真的。

/// Stage 6e **之前**的 `RoutingSignalEntry` 形状：7 个永久字段 + 2 个待删的
/// optional 调试列。仅用于在测试里造一个「旧版本写下的」store。
enum LegacyTelemetrySchema {
    @Model
    final class RoutingSignalEntry {
        var kind: String = ""
        var provider: String = ""
        var deviceTier: String = ""
        var latencyMs: Int = 0
        var schemaValid: Bool = false
        var accepted: Bool?
        var timestamp: Date = Date()
        /// 对应旧版两个 optional String 调试列（见文件头说明，故意不用原名）
        var legacyDroppedDebugA: String?
        var legacyDroppedDebugB: String?

        init(
            kind: String,
            provider: String,
            deviceTier: String,
            latencyMs: Int,
            schemaValid: Bool,
            accepted: Bool? = nil,
            timestamp: Date = Date(),
            legacyDroppedDebugA: String? = nil,
            legacyDroppedDebugB: String? = nil
        ) {
            self.kind = kind
            self.provider = provider
            self.deviceTier = deviceTier
            self.latencyMs = latencyMs
            self.schemaValid = schemaValid
            self.accepted = accepted
            self.timestamp = timestamp
            self.legacyDroppedDebugA = legacyDroppedDebugA
            self.legacyDroppedDebugB = legacyDroppedDebugB
        }
    }
}

@Suite("RoutingSignalEntry lightweight migration (Stage 6e)")
struct RoutingSignalEntryMigrationTests {

    /// 每个用例用独立临时目录，互不串扰；结束即删。
    private static func withTemporaryStoreURL(
        _ body: (URL) throws -> Void
    ) throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vitalmodels-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("Telemetry.store"))
    }

    @Test("旧库（含已删调试列）用新 schema 打开不 crash，旧行仍可读")
    func legacyStoreOpensUnderNarrowedSchema() throws {
        try Self.withTemporaryStoreURL { url in
            let writtenAt = Date(timeIntervalSince1970: 1_700_000_000)

            // 1) 以旧 schema 落盘两行，其中一行填了待删的调试列。
            do {
                let legacySchema = Schema([LegacyTelemetrySchema.RoutingSignalEntry.self])
                let legacyConfig = ModelConfiguration(
                    schema: legacySchema,
                    url: url,
                    cloudKitDatabase: .none
                )
                let legacyContainer = try ModelContainer(for: legacySchema, configurations: [legacyConfig])
                let context = ModelContext(legacyContainer)
                context.insert(LegacyTelemetrySchema.RoutingSignalEntry(
                    kind: "chat",
                    provider: "openai",
                    deviceTier: "cloudOnly",
                    latencyMs: 1234,
                    schemaValid: true,
                    accepted: true,
                    timestamp: writtenAt,
                    legacyDroppedDebugA: "legacy-debug-a",
                    legacyDroppedDebugB: "legacy-debug-b"
                ))
                context.insert(LegacyTelemetrySchema.RoutingSignalEntry(
                    kind: "trainingAdvice",
                    provider: "onDevice",
                    deviceTier: "onDeviceCapable",
                    latencyMs: 42,
                    schemaValid: false,
                    accepted: nil,
                    timestamp: writtenAt
                ))
                try context.save()
            }

            // 2) 同一个文件，用收窄后的当前 schema 打开。构造器抛错即迁移失败
            //    —— 在真机上等价于升级后启动即崩。
            let currentSchema = Schema([RoutingSignalEntry.self])
            let currentConfig = ModelConfiguration(
                schema: currentSchema,
                url: url,
                cloudKitDatabase: .none
            )
            let migratedContainer = try ModelContainer(for: currentSchema, configurations: [currentConfig])
            let migratedContext = ModelContext(migratedContainer)

            let rows = try migratedContext.fetch(FetchDescriptor<RoutingSignalEntry>())
            #expect(rows.count == 2, "旧行应被保留（lightweight migration 只丢被删的列）")

            let chat = try #require(rows.first(where: { $0.kind == "chat" }))
            #expect(chat.provider == "openai")
            #expect(chat.deviceTier == "cloudOnly")
            #expect(chat.latencyMs == 1234)
            #expect(chat.schemaValid == true)
            #expect(chat.accepted == true)
            #expect(chat.timestamp == writtenAt)

            let advice = try #require(rows.first(where: { $0.kind == "trainingAdvice" }))
            #expect(advice.accepted == nil)
            #expect(advice.latencyMs == 42)
        }
    }

    @Test("迁移后 entity 只剩 7 个永久字段 —— 旧调试列不再被 schema 持有")
    func migratedEntityExposesOnlyPermanentFields() throws {
        try Self.withTemporaryStoreURL { url in
            do {
                let legacySchema = Schema([LegacyTelemetrySchema.RoutingSignalEntry.self])
                let legacyConfig = ModelConfiguration(
                    schema: legacySchema,
                    url: url,
                    cloudKitDatabase: .none
                )
                let legacyContainer = try ModelContainer(for: legacySchema, configurations: [legacyConfig])
                let context = ModelContext(legacyContainer)
                context.insert(LegacyTelemetrySchema.RoutingSignalEntry(
                    kind: "chat",
                    provider: "openai",
                    deviceTier: "cloudOnly",
                    latencyMs: 7,
                    schemaValid: true,
                    legacyDroppedDebugA: "legacy-debug-a",
                    legacyDroppedDebugB: "legacy-debug-b"
                ))
                try context.save()
            }

            let currentSchema = Schema([RoutingSignalEntry.self])
            let currentConfig = ModelConfiguration(
                schema: currentSchema,
                url: url,
                cloudKitDatabase: .none
            )
            let migratedContainer = try ModelContainer(for: currentSchema, configurations: [currentConfig])

            // 分步展开：整条链塞进 `#require` 会让类型检查器超时。
            var entities: [Schema.Entity] = []
            for configuration in migratedContainer.configurations {
                entities.append(contentsOf: configuration.schema?.entities ?? [])
            }
            let entity = try #require(entities.first(where: { $0.name == "RoutingSignalEntry" }))
            let attributes = Set(entity.attributes.map(\.name))
            #expect(attributes == [
                "kind", "provider", "deviceTier", "latencyMs", "schemaValid", "accepted", "timestamp",
            ], "迁移后仍暴露非永久字段（FR-017 永久态被打破）；实际: \(attributes)")
        }
    }
}
