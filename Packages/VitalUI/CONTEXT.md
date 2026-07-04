---
layer: VitalUI
role: 跨 app target 共享的 SwiftUI 组件；轻量，仅含不依赖业务逻辑的通用 UI
depends_on: [VitalModels]
depended_by: []
red_lines:
  - 仅放不含业务逻辑的通用 UI；业务逻辑住 Packages 其它层或 app target（宪法 III）
  - UI 字符串必须用 String(localized:) / NSLocalizedString 引用 xcstrings，禁止硬编码中文（宪法 VI）
  - Swift 6 strict concurrency，View/Modifier 遵守 MainActor isolation（宪法 II）
roles:
  Runtime: [HapticManager]
  UI:      [SnackbarMode, SnackbarModifier, DataStoreErrorView]
test: swift test --package-path Packages/VitalUI
owns: [DataStoreErrorView, SnackbarModifier, HapticManager]
---

# VitalUI Context

## 职责

跨 app target 共享的 SwiftUI 组件。轻量 package，仅含不依赖业务逻辑的通用 UI。

## 组件

| 组件 | 说明 |
|------|------|
| DataStoreErrorView | SwiftData 容器初始化失败时的错误展示 |
| SnackbarModifier | 底部浮层通知（自动消失），`.snackbar(isPresented:content:)` modifier |
| SnackbarMode | Snackbar 显示模式枚举（timed / persistent） |

## 使用方式

```swift
.snackbar(isPresented: $showError) {
    Label("操作失败", systemImage: "exclamationmark.triangle")
}
```

## 依赖

- VitalModels
