---
layer: Prototype
role: 与生产 app 隔离的 SwiftUI 视觉原型与截图导出 layer
paths: [Prototype]
test_paths: []
gate_tier: local-fast
build: swift build --package-path Prototype
depends_on: [DesignKit]
depended_by: []
red_lines:
  - 仅用于视觉探索与截图导出，不嵌入生产 app target
  - 只依赖 DesignKit；不得依赖 VitalModels、SwiftData 或 AppUI
  - 原型冻结后以独立任务移植到生产 layer，不直接共享原型实现
  - Swift 6 strict concurrency（宪法 II）
roles:
  UI: [WorkoutKeyboardPrototype, WorkoutListPrototype]
test: swift build --package-path Prototype
owns: [visual prototypes, screenshot exporters]
---

# Prototype Context

## 职责

`Prototype` 是 preview/screenshot 驱动的视觉探索 layer，与生产 app 代码隔离。它只消费
`DesignKit` token 和组件；验证命令是该独立 SPM package 的 `swift build`。

设计确定后，在对应生产 layer 建独立实现任务；不让原型 target 成为生产依赖。
