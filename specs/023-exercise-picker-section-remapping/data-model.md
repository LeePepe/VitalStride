# Data Model: 动作选择分区语义重映射

## Persistent model

本 feature 不新增或修改持久字段。

- `Exercise.equipment` 继续保存 `Equipment`。
- `Exercise.section` 继续是由 `equipment.section` 派生的非持久计算值。
- 不修改 initializer、SwiftData model schema、CloudKit configuration、catalog version 或 Seeder migration。

## Value semantics

### Equipment

原始 catalog taxonomy。29 个 raw values 全部保留；`assisted` 与 `weighted` 仍是合法原始标签。

### ExerciseSection

picker 的产品展示分类。既有 public cases 与 raw values 保持兼容；当前 catalog 只产生 12 个非空 section。合并后的 legacy cases可解码但不再由 `Equipment.section` 产生。

### Other Section

显式接收 `contracts/section-mapping.md` 中列出的 17 个 Equipment 值。成员资格不随 catalog 当前数量或用户筛选动态改变。

## State transitions

无迁移。现有 Exercise 在下一次读取 `section` 时立即采用新映射；`equipment` 值保持不变。
