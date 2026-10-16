# B 细化交付

**[最新公开画廊](https://leepepe.github.io/vitalstride/workout-layouts/)** · [离线画廊](index.html) · 2026-10-16

用户选择 B。本次由 my-designer 主导，只改隔离的 Prototype；生产 AppUI 尚未移植。

## 本次结果

- 64pt左侧动作导航与右侧连续组表分别可滚动。右侧可见动作更新侧栏高亮；点击侧栏跳转；末尾预留足够空间定位最后动作。
- 浏览位置与操作对象分开。滚动不提交草稿、不改目标；侧栏铅笔＋“编辑”、底栏或键盘footer、提交按钮组号共同指示目标。常态和输入时均可定位返回。
- 保留独立60pt snackbar，位于键盘 / 主操作上方。休息、撤销均可用；撤销展示被删动作和原组号，休息并存时第二行继续倒计时。
- 操作浮层使用Apple玻璃层次，数据表保持不透明；RPE / 筛选选中状态增加描边和勾；浅色语义色对比度修正。
- 主题色继续单独设计。动作选择保持侧栏＋双列，搜索、Filter、取消、已选清单、确认都在底部。

原生 iOS26/macOS26+使用 `.glassEffect(.regular)`；旧系统为material，Reduce Transparency使用不透明面板。滚动动画遵从Reduce Motion。数据行不使用实时玻璃，倒计时只更新对应子视图，可见section事件不传逐像素偏移。

## 验证与可运行入口

```bash
swift run --package-path Prototype CompactWorkoutStudio
swift build --package-path Prototype
swift test --package-path Prototype
swift run --package-path Prototype CompactWorkoutStudio --render-b Prototype/CompactEvidence/b-shots
```

工作室默认B。`STUDIO_LANGUAGE=en`可切英文。构建通过、14个旅程测试通过；新增两项验证浏览不修改/提交草稿，以及空/未知可见目标不破坏导航、重复定位仍可触发。原有任意组输入、无效草稿阻止切换、保存/放弃、记组、删除/撤销、休息、选择器缓存测试继续通过。

32张新图覆盖明暗、常态/输入/休息/撤销及组合、跨动作浏览、More、RPE、动作选择、筛选、无结果、375pt输入＋休息。V2的52张图和12张对比板保留为历史。

画廊脚本检查覆盖28种状态/主题组合，84个图像引用全部存在；237个本地化key均有中英文，125个组件源码字面量引用可解析。完成圈黑勾/绿色背景对比约9.46:1，浅色删除文字/面板约5.8:1（导出像素取样）。SwiftLint本机不可用。

独立截图全量评审30/35，最后一项侧栏文字对比度P1修正后已独立确认解决，保留原评分。详细证据见 [B 设计评审](b-review.md)，额外对比度初评见 [核查报告](b-review-contrast-initial.md)。旧B留白问题已用连续动作内容解决，不再通过隐藏功能或缩小触控目标换密度。

## 证据边界

这些是macOS ImageRenderer的手机尺寸图（393 / 375×852pt，2×），采用演示数据。ImageRenderer不能采样原生窗口背后的Liquid Glass，导出分支明确使用material近似。滚动定位图从对应section顶端导出相同组件，不是实际拖动截图。

原生窗口自动交互检查未获工具授权；实际手势联动、焦点、末尾内容可达性、触控命中、iOS Simulator、真实Dynamic Type、VoiceOver及原生glass光学效果均尚未验证。编译和状态测试不能替代这些交互验收。

生产性能源码审计仍见 [性能证据](../RedesignEvidence/compact-performance-audit.md)。这轮没有改生产数据查询、UIKit键盘宿主或持久化路径，没有Instruments/Release测量，不能声称生产卡顿已修复。生产合入继续按PR-required流程另行交付；GitHub Pages仅发布静态设计证据。
