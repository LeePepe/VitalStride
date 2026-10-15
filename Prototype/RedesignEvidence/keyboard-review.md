# 设计评审结果 · 配套训练键盘

**最终总分：30 / 35** — 三种键盘结构成立，明暗主题和重量/次数切换清楚；K3 窄屏裁切已修复，复制目的与工具入口已明确。无截图可确认的未解决 P0，真实 iOS 平台验收仍待完成。

本次是独立键盘评审，分数不继承页面评审的 31 / 35。依据为 [keyboard-north-star.md](keyboard-north-star.md) 和原七维 rubric；仅评价隔离的 Native SwiftUI / DesignKit 演示原型，不涉及生产接入。

## 实际检查范围

首轮通过 `view_image` 查看了 `keyboard-comparisons/` **全部 18 张双输入板**：Tide、Graphite、Ember × grid、thumb、sequence × light/dark。每张左侧重量、右侧次数，覆盖 36 个核心输入画面。

另实际查看了 `keyboards/` 的 resting、undo、invalid 各 light/dark 共六张，以及 K1 grid light、K2 thumb dark、K3 sequence light 的三张 375pt `large-narrow` 代表图。为核对触控尺寸、字段名称与键盘 trait，读取了 `WorkoutStudioKeyboard.swift` 和少量页面编辑上下文源码，没有改源码，没有运行点击或 VoiceOver。

最终重导后实际复看了 [Tide K2 light](keyboard-comparisons/tide-thumb-light.png)、[Graphite K2 dark](keyboard-comparisons/graphite-thumb-dark.png)、[Ember K3 light](keyboard-comparisons/ember-sequence-light.png)、[Tide K3 dark](keyboard-comparisons/tide-sequence-dark.png)，以及 K3 375pt [light](keyboards/tide-keyboard-sequence-weight-light-large-narrow.png) / [dark](keyboards/tide-keyboard-sequence-weight-dark-large-narrow.png)。本轮没有重复查看未改变的全部 18 张板。工具页第一项及完整复制文案通过源码和 `Studio.xcstrings` 核对，未运行打开工具页的 UI 点击。

## 维度评分

| 维度 | 分数 | 观察 |
|---|---:|---|
| 间距与留白 | 4 / 5 | 数字区和字段条间距稳定；K1 大键面、K2 侧栏、K3 预设的密度区别明显。普通画布中当前组到键盘之间留白偏多，但保留了可识别上下文。K3 窄屏已改为完整可见的只读卡片。 |
| 字体层级 | 4 / 5 | 24pt 等宽数字键、21pt 字段数值、12–14pt 字段/快捷说明区分清楚；键盘数字易扫描。固定字号的真实 iOS 大字表现尚未验证。 |
| 色彩与对比 | 5 / 5 | 主强调色用于当前字段和操作，数字键保持中性；Graphite 的描边与黑白 CTA、Ember 的暖色和较圆键帽、Tide 的青蓝层次均可辨认。invalid 使用图标、红字和禁用态，不只靠颜色。未做逐像素对比度审计。 |
| 层级与表面 | 4 / 5 | 字段选择、数字区、主操作层级明确；K1/K2“下一项 / 保存输入”与 K3“保存并记组”文案有区分。大字时上方只读上下文避免了重复编辑/完成控件与键盘争抢空间。 |
| 分组与对齐 | 5 / 5 | 1–9 / 小数 / 0 / 删除的空间顺序一致；字段名、值、单位对齐。K2 侧栏与 K3 次数预设分组明确；“复制到 / 下一组”和“工具”已成为可读入口，没有挤压数字区。 |
| 数据可视化 | 4 / 5 | 本任务的可视化是训练完成进度、当前组状态、选中字段及休息倒计时；这些信息清楚，未为了打分添加无关图表。静态图不证明动态计时、复制后反馈或提交后的状态迁移。 |
| 平台适配 | 4 / 5 | SwiftUI 外观和按键尺寸方向合理；源码有字段身份、选中 trait、键盘键 trait。K3 375pt light/dark 当前组已完整位于键盘上方；真实 iOS 键盘、安全区、Dynamic Type 与 VO 运行仍未证明。 |
| **合计** | **30 / 35** | **原 P0 与两个文案/入口 P1 已解决；仍有平台验收 P1。** |

## 必修项（P0）

**无未解决的截图 P0。** 首轮 K3 375pt 卡片底部按钮裁切已关闭：最新 [light](keyboards/tide-keyboard-sequence-weight-light-large-narrow.png) 与 [dark](keyboards/tide-keyboard-sequence-weight-dark-large-narrow.png) 改为只读组号与重量×次数，卡片约 76pt 高；底部到键盘分隔线约 27pt，没有残留半截操作文字，数字键仍为 44pt。该修复只证明本次导出状态，不替代真实 iOS 大字验收。

## 首轮发现处理状态

| 首轮发现 | 最终状态 | 实际证据 |
|---|---|---|
| P0：K3 375pt 当前组操作被裁切 | **已解决** | 最新 K3 light/dark 只读上下文完整可见，保留约 27pt 到键盘分隔线的留白。 |
| P1：复制目的不明确 | **已解决，限视觉与标注文案** | K2/K3 均显示两行“复制到 / 下一组”；完整工具与 accessibility 文案为“复制到下一组（覆盖已有输入）”。按钮保持 64pt 宽与至少 44pt 高。实际复制/覆盖反馈没有由本评审运行核验。 |
| P1：放弃草稿入口不易发现 | **已解决，限入口和源码顺序** | 省略号增加可见 12pt“工具”，48×52pt 入口未挤压主操作。`toolsSheet` 第一项为“放弃当前组输入草稿”，至少 44pt 高；该顺序通过源码核对，未运行工具页点击。 |
| P1：真实平台验收缺失 | **未解决，明确披露** | 仍是 ImageRenderer 手机尺寸渲染，没有 iOS Simulator / VO / detached inputView / 性能运行证据。 |

## 建议项（P1）

**真实平台验收仍缺失。** 字段条高 48pt，普通数字键高 48pt、K3 高 44pt、主操作高 52pt，源码符合目标；这不等于实际单手可达性或 VO 使用已通过。迁移时需在 iOS Simulator 的 375/393pt、light/dark、accessibility1 及更大字号下验证键盘高度与 safe area；错误说明需能换行，字段和快捷项不得靠缩字容纳。检查 VO 是否分别读出字段、值、单位、选中状态，以及“保存输入”和“保存并记组”的不同作用。实际运行复制覆盖、草稿放弃和记组后的反馈；K2 左手镜像也需实际导出和点击验证，本轮双输入板没有展示镜像后的画面。

## 做得好的地方（保留）

- **K1 全宽数字**适合作为默认：键面大，数字区熟悉，重量到次数的顺序明确。
- **K2 拇指侧栏**确实是结构变化：±2.5 / ±1、上次和复制集中在独立侧栏；数字区仍维持相同顺序，没有为了镜像把数字倒过来。
- **K3 连续记组**增加次数预设、复制与明确的“保存并记组”，不是只改主按钮颜色；375pt 回退改成只读当前组后，结构也保持完整。
- [休息 light](keyboards/tide-keyboard-grid-weight-light-resting.png) 与 [休息 dark](keyboards/tide-keyboard-grid-weight-dark-resting.png) 把计时、±10 秒、跳过收为单行，当前组仍在键盘上方；[撤销 light](keyboards/tide-keyboard-grid-weight-light-undo.png) 与 [撤销 dark](keyboards/tide-keyboard-grid-weight-dark-undo.png) 也保留了清楚的撤销入口，没有盖住数字区。
- [无效次数 light](keyboards/tide-keyboard-grid-reps-light-invalid.png) 与 [无效次数 dark](keyboards/tide-keyboard-grid-reps-dark-invalid.png) 对次数 0 显示范围说明，并禁用保存和收键盘；没有偷偷改成别的数。
- [K1 375pt](keyboards/tide-keyboard-grid-weight-light-large-narrow.png)、[K2 375pt](keyboards/tide-keyboard-thumb-weight-dark-large-narrow.png) 的当前组卡片没有可见水平溢出；这两张的布局回退值得保留。

## 验收边界

所有图均为 **macOS ImageRenderer 的手机尺寸渲染**，不是 iOS Simulator 截图；大字图只检查布局 fallback，未证明真实 iOS 字体缩放。没有运行 UI 点击、VoiceOver、UIKit detached inputView、真实训练数据、输入延迟、帧时、热或能耗测量。休息截图也不证明后台计时正确。这里没有把渲染速度、源码标注或演示图当作性能与可访问性通过证据。
