---
scope: Packages
routes:
  - paths: [Packages/AIService]
    context: Packages/AIService/CONTEXT.md
    kind: layer
  - paths: [Packages/DesignKit]
    context: Packages/DesignKit/CONTEXT.md
    kind: layer
  - paths: [Packages/HealthKitService]
    context: Packages/HealthKitService/CONTEXT.md
    kind: layer
  - paths: [Packages/TelemetryKit]
    context: Packages/TelemetryKit/CONTEXT.md
    kind: layer
  - paths: [Packages/VitalModels]
    context: Packages/VitalModels/CONTEXT.md
    kind: layer
  - paths: [Packages/VitalUI]
    context: Packages/VitalUI/CONTEXT.md
    kind: layer
---

# Packages Context

`Packages/**` 是顶层可展开 scope，不是产品 layer。先按本表定位一个 package，再只读取该 package 的
`CONTEXT.md`。

| Package layer | Context |
|---|---|
| AIService | `Packages/AIService/CONTEXT.md` |
| DesignKit | `Packages/DesignKit/CONTEXT.md` |
| HealthKitService | `Packages/HealthKitService/CONTEXT.md` |
| TelemetryKit | `Packages/TelemetryKit/CONTEXT.md` |
| VitalModels | `Packages/VitalModels/CONTEXT.md` |
| VitalUI | `Packages/VitalUI/CONTEXT.md` |
