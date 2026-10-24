# 配套训练键盘交付

**[打开九种键盘对比 →](keyboard.html)** · [返回页面画廊](index.html) · 2026-10-16 · my-designer 主导。

动作选择页与训练页原来各 9 种组合。配套键盘现在也有 **3 种风格 × 3 种布局 = 9 种组合**，每种分别呈现重量输入、次数输入，以及 light/dark。核心 36 张，加休息/撤销/无效输入六张、375pt 大字回退六张，共 **48 张键盘屏幕图、18 张双输入对比板**。原页面与键盘合计 102 张屏幕图、36 张对比板。

## 推荐方向

| 方向 | 预览 | 适用情境 |
|---|---|---|
| **默认：S1 青蓝 × K1 全宽数字** | [浅色](keyboard-comparisons/tide-grid-light.png) · [深色](keyboard-comparisons/tide-grid-dark.png) | 大键面、熟悉数字顺序，重量 → 次数 → 保存输入 |
| S2 石墨 × K2 拇指侧栏 | [浅色](keyboard-comparisons/graphite-thumb-light.png) · [深色](keyboard-comparisons/graphite-thumb-dark.png) | 单手微调、调用上次演示记录、复制下一组；左右手可切换 |
| S3 暖色 × K3 连续记组 | [浅色](keyboard-comparisons/ember-sequence-light.png) · [深色](keyboard-comparisons/ember-sequence-dark.png) | 8/10/12 次预设与明确的保存并记组，适合熟练记录 |

三种风格全部可搭配三种键盘。页面布局与键盘布局是独立选项；导图采用 K1/L1、K2/L2、K3/L3 的代表搭配，没有把所有跨轴排列称作已审核组合。

## 已实现的交互

- 打开字段即全选旧值，首个数字替换；重量最多两位小数，次数不允许小数。
- 重量与次数共享本组草稿，切换不丢输入。顶部收键盘保存两个字段，不记组；K1/K2 主按钮依次切到次数、保存输入；K3 明确保存并记组、开始休息。
- 空值、非有限数、重量超出 0–999kg、次数不是 1–999 整数时，显示说明并阻止提交，不在提交时悄悄改值。
- 草稿绑定原动作 ID 与组 ID，切换动作不会写错目标；连续提交不会重复记组。删除编辑目标会退出草稿，撤销可恢复原组。
- K2 提供 ±2.5kg/±1、上次演示记录、复制到下一组。左右手切换只移动侧栏，保留数字顺序。
- 复制立即覆盖下一组输入；仅在当前组是末尾时追加一组。取消草稿不会撤销已执行的复制。界面短标签标明下一组，工具项与可访问性标签说明覆盖已有输入，执行后显示复制提示。
- 工具入口有可见文字，第一项是放弃本组草稿。当前组保持在键盘上方；窄屏大字状态用只读组号与重量×次数，避免重复操作挤压空间。
- 休息编辑时收成单行；撤销优先显示，休息仍按结束日期继续。键盘不运行独立计时器。

单侧重量、递增/递减子组、循环次数桶及 UIKit detached inputView 的 Theme 注入属于生产能力；工具页说明本轮未接入。迁移必须按 [已有流程审查](workflow-audit.md) 保留，不能把固定预设误当作完整生产合同。

## 验证与边界

- SwiftPM 路由，`swift build --package-path Prototype` 成功；`swift test --package-path Prototype` 的 **8 项 Swift Testing 流程通过**，其中四项专门覆盖键盘草稿、安全提交、复制与目标身份。最后的文案/入口修改再次构建成功。
- 独立截图评审 **30/35，无未解决的截图 P0**；整改记录见 [keyboard-review.md](keyboard-review.md)。K3 窄屏大字当前组裁切已修复并重新渲染；复制目的与工具入口已补充文字。
- 图像数量与尺寸核对通过；键盘画廊 24 种筛选组合的 252 个图片路径及 252 个图片链接、静态文档链接通过 DOM 桩与文件检查。169 个 catalog key 均有中英翻译，93 个静态字面量引用均可解析；英文另导出至临时目录，抽查 K2 重量、K3 次数及边界提示。此为脚本和文件验证，未声称浏览器点击通过。
- 原型只依赖 DesignKit，不读取真实训练或健康数据；无新增第三方 Swift 包。`swiftlint` 本机未安装，未执行。
- 数字键高 48pt，K3 为 44pt，字段 48pt，主操作 52pt；源码尺寸不等同于实际点击和可访问性通过。
- 图片由 **macOS ImageRenderer** 导出，常规为 393×852pt@2×，窄屏为 375×852pt@2×，不是 iOS Simulator 图。UI 自动化未能访问原生工作室，浏览器工具不可用；没有声称 GUI 点击、VoiceOver 或真实系统键盘通过。
- 真实 iOS 安全区、完整 Dynamic Type、VoiceOver、左手镜像可达性，以及输入延迟、帧时、能耗仍需迁移时验证。键盘避免图片、模糊、网络、历史查询及输入时持久化，只更新小型草稿；这些是实现原则，尚无生产性能测量结果。

## 运行与导出

从仓库根目录运行，选择“数字输入”场景，在“配套训练键盘”切换布局：

```bash
swift run --package-path Prototype WorkoutDesignStudio
swift build --package-path Prototype
swift test --package-path Prototype
swift run --skip-build --package-path Prototype WorkoutDesignStudio --render-keyboards Prototype/RedesignEvidence/keyboards
python3 Prototype/RedesignEvidence/make_comparisons.py
open Prototype/RedesignEvidence/keyboard.html
```

英文演示用 `STUDIO_LANGUAGE=en swift run --package-path Prototype WorkoutDesignStudio`。

分支：`agent/design/workout-explorations-20261016`。本轮为隔离的 Prototype 设计交付，尚未迁入生产 App。
