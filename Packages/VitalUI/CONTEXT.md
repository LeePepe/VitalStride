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
