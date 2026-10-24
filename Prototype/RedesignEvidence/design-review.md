# 设计评审结果 · 最终候选复评

**总分：31 / 35** — 可用于三种风格 × 三种布局的方向评选。首屏密度、Board 总览、完成文字与结束状态文案已处理；未发现截图可确认的 P0，仍保留真实 iOS 平台验收的 P1 缺口。

本次由独立设计评审子代理完成，对照 [north-star.md](north-star.md) 和原七维 /35 rubric。评审优先级只描述设计问题，不是代码审查或 PR shipping verdict。

## 实际检查范围

第二轮通过 `view_image` 实际查看了 `comparisons/` 的 **18 张图**：Tide、Graphite、Ember 各自的 Flow、Focus、Board，全部覆盖 light/dark。每张包含动作选择与训练两页。另查看了 **12 张状态单图**：Tide Flow 键盘 light、休息 dark、撤销 light、空库 dark、无搜索结果 light、结束 dark，以及三种布局各自的 picker/workout 窄屏大字布局 fallback light。没有声称逐张检查所有 54 张单图。

最后一轮重新导出后，本次小范围复核实际重看了 [Tide Flow light](comparisons/tide-flow-light.png)、[Graphite Flow dark](comparisons/graphite-flow-dark.png)、[结束 dark](shots/tide-flow-workout-dark-finished.png)，并看了 `/tmp/vitalstride-design-english/graphite-flow-workout-dark.png`，确认英文短词 “Done” 没有截断。本次没有再次逐张查看全部 18 张对比图。

仅为核对上一轮可访问性修复，读取了 `WorkoutStudioView.swift` 的字段与组容器标注；没有修改源码。没有运行 GUI 点击、VoiceOver、iOS Simulator、FPS 或能耗测试。

## 维度评分

| 维度 | 分数 | 评审依据 |
|---|---:|---|
| 间距与留白 | 5 / 5 | Flow 的单列密度稳定；Focus 首屏由四张完整卡改善到六张；Board 压缩后能同时辨认当前与两个后续动作，没有靠缩小输入区换空间。 |
| 字体层级 | 4 / 5 | 标题、动作名、数字、元信息层级清楚；“当前”以 12pt 为基准，Focus 数字以 58pt 为基准，已使用 ScaledMetric；Graphite 标题更紧。真实 iOS 字体放大后的排版仍需验证。 |
| 色彩与对比 | 5 / 5 | 三种强调色与成功语义分开；主文和数值在明暗两主题均清楚。Tide 青蓝、Graphite 黑白按钮、Ember 暖色与 serif 标题有可见区别。未进行逐像素对比度数值审计。 |
| 层级与表面 | 4 / 5 | 当前组的亮度层次与底部主操作明确，休息状态没有双主按钮竞争；结束画面已改为“训练已结束 / 完成”。Board 整卡强调仍比 Flow 更重，当前组的优先级主要由输入表面区分。 |
| 分组与对齐 | 5 / 5 | 组表、历史、当前输入、动作选择顺序及后续动作分组清楚；Board 现在兑现了总览价值；字段与表头保持对齐。 |
| 数据可视化 | 4 / 5 | 完成条、逐组短条、休息条及倒计时足够表达操作状态；没有为了得分塞入无关图表。常规组表现有 check +“完成 / Done”，静态状态表达清楚；动态计时与状态切换未由本评审运行核验。 |
| 平台适配 | 4 / 5 | 原生 SwiftUI 视觉、明暗适配、56pt 数字输入与纵向 fallback 方向合理；字段身份与组容器已有源码标注。系统键盘、安全区、真实字体放大及屏幕阅读器运行尚未证明。 |
| **合计** | **31 / 35** | **原型视觉方向达到可评选水平；生产验收未执行。** |

## 必修项（P0）

**无截图可确认的 P0。** 检查范围内未见关键文字溢出、主操作消失、明暗主题失效或当前数值被键盘遮挡等明显硬伤。不把“没有运行平台测试”误写为测试通过。

## 第一轮每条处理状态

| 第一轮问题 | 本轮状态 | 实际复核 |
|---|---|---|
| 1. Board 首屏只有一个动作 | **已解决，限本轮常规画布** | [Tide Board light](comparisons/tide-board-light.png)、[Graphite Board dark](comparisons/graphite-board-dark.png)、[Ember Board light](comparisons/ember-board-light.png) 的活动卡已由约 454pt 缩至约 336pt，热身可展开，当前 + 后续两个动作的名称与组数可见。 |
| 2. 当前标签 10pt、数字 VO 身份不足、空动作按钮 | **视觉和源码标注已解决；运行验证未做** | “当前”以 12pt 为基准并使用 ScaledMetric；数字字段高 56pt；字段名称区分重量/次数，组行有 contain 容器；非当前字段改文本。字号缩放结果与 VO 最终朗读顺序不由静态图证明。 |
| 3. 空库没有可执行入口 | **原型范围已解决** | [空库 dark](shots/tide-flow-picker-dark-emptyLibrary.png) 增加了明确的“载入演示动作库”按钮。它是 demo 操作，不应被描述成生产导入已完成。 |
| 4. Focus 选择卡留白过多 | **已解决** | [Tide Focus dark](comparisons/tide-focus-dark.png)、[Graphite Focus light](comparisons/graphite-focus-light.png)、[Ember Focus dark](comparisons/ember-focus-dark.png) 均可完整辨认六卡，卡高约 112–114pt，名称和器械没有因压缩被截断。 |
| 5. Graphite 风格差异偏弱 | **明显改善，仍是克制的系统型方案** | [Graphite Flow light](comparisons/graphite-flow-light.png) 的标题更紧、分隔更明确、表面轮廓更方，配合黑白 CTA 足以形成第三候选；胶囊筛选仍沿用共同交互。无需为追求差异改变操作语义。 |
| 6. 键盘、屏幕边界、辅助功能缺少 iOS 证据 | **未解决，明确披露** | 这批图仍是 macOS ImageRenderer 手机尺寸画面。GUI 工具拒绝 app 访问，未做 UI 点击或 VO 运行；大字图只证明 fallback 分支布局，没有证明 macOS 字体按 iOS accessibility1 比例放大。 |

## 最后一轮 P1 复核

| 第二轮剩余问题 | 状态 | 实际复核 |
|---|---|---|
| 常规组表只有完成图标，缺少文字 | **已解决** | 最新 [Tide Flow light](comparisons/tide-flow-light.png) 和 [Graphite Flow dark](comparisons/graphite-flow-dark.png) 均显示 20pt check + 基准 12pt 可缩放“完成”，放在 44×56pt 区域内；英文单图显示短词 “Done”，没有挤压数值或截断。 |
| 结束总结顶栏仍为进行中 | **已解决** | 最新 [finished dark](shots/tide-flow-workout-dark-finished.png) 已显示“训练已结束 / 完成”，关闭图标也与结束状态一致。 |
| 固定字号实现与真实大字验收 | **实现已改善；真实平台验收仍未完成** | 当前标签、完成文字与 Focus 数字已使用 ScaledMetric；源码修复不等于 iOS 字体放大、键盘与 VO 运行通过。 |

评分保持 **31 / 35**。本次小范围修正关闭了两个具体 P1，不因修复条目数量自动升分。

## 剩余建议项（P1）

**真实 iOS 大字、键盘与屏幕阅读器验收仍需完成。** [Flow 窄屏训练](shots/tide-flow-workout-light-normal-large-narrow.png)、[Focus 窄屏训练](shots/tide-focus-workout-light-normal-large-narrow.png)、[Board 窄屏训练](shots/tide-board-workout-light-normal-large-narrow.png) 的纵向组卡避免了表格硬挤；这是正确策略。当前标签、完成文字和 Focus 数字虽已使用 ScaledMetric，macOS 导出仍没有证明 iOS accessibility1 或更大档位的实际字体缩放结果。迁移时在 375/393pt、accessibility1/更大档位用 iOS Simulator 验证，按需将编辑重量、编辑次数、完成按钮纵向排列，每项至少 44pt、项间 8pt，输入区域到键盘至少 16pt。另实测重量/次数/组号的 VO 顺序，避免只检查源码 label。

## 保留与方向建议

- **默认推荐 Tide × Flow**：选择、上次记录、当前输入、完成路径最平衡，便于高频记录。
- **Focus 是单手训练候选**：大数字 + ±2.5kg / ±1 步进比普通表格更容易抬眼确认；本轮选动作的六卡密度也更合理。
- **Board 是计划管理候选**：后续动作现在可见，分类侧栏与折叠卡的布局区别成立；切勿在生产迁移时恢复过高的活动卡。
- Graphite 适合偏工具感、低色彩噪声的方向；Ember 的 serif 标题和暖色区是三者中最鲜明的风格变化。保留同一数据与操作语义，方便用户只比较设计选择。
- [键盘 light](shots/tide-flow-workout-light-keyboard.png) 的数值、单位、小数、删除和完成可见；[休息 dark](shots/tide-flow-workout-dark-resting.png) 的计时、±10s 和跳过明确；[撤销 light](shots/tide-flow-workout-light-undo.png) 不遮住当前组；[无结果 light](shots/tide-flow-picker-light-noResults.png) 保留已选动作。这些是值得保留的具体改进。

## 验收边界

**本轮交付是隔离的 SwiftUI 设计候选及其渲染证据。** 手机状态栏、home indicator 与键盘在图中属于原型内容，不能称为 iOS Simulator 截图。未完成真实 Dynamic Type 放大、系统键盘、安全区、VoiceOver 或 UI 自动化点击验收；GUI 工具拒绝访问不能被改写为可访问性 PASS。静态渲染也不支持 FPS、热、能耗或真实训练数据性能结论。本轮没有执行合成搜索测量。构建与交互模型测试由执行者单独报告，均不替代本次视觉复评或生产平台验收。
