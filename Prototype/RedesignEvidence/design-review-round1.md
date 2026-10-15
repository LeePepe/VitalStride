# 设计评审结果 · 第一轮

**总分：29 / 35** — 三种布局能辨认，训练主操作清晰；可以用于方向评选，仍有密度、总览能力与可访问性细节要处理。

评审人是独立子代理。实际通过 `view_image` 检查了九个组合：Tide Flow light / Focus dark / Board light，Graphite Flow dark / Focus light / Board dark，Ember Flow light / Focus dark / Board light。每种风格均覆盖了浅色与深色。另检查了 Tide Flow 的键盘、休息、撤销、375pt 窄屏大字、无结果和空库单张 PNG。对照依据为 [north-star.md](north-star.md) 与七维 rubric。以下 P0/P1 是视觉评审优先级，不是仓库 PR gate verdict。

## 维度评分

| 维度 | 分数 | 实际观察 |
|---|---:|---|
| 间距与留白 | 4 / 5 | 20pt 页面边距、12/16pt 组件间距一致；Flow 密度合适。Focus 选择卡与 Board 展开区仍偏高。 |
| 字体层级 | 4 / 5 | 标题、动作名、表格数值、辅助信息层级明确；等宽数字有效。当前组的 10pt 标签过小，Graphite 的紧凑排版特征尚弱。 |
| 色彩与对比 | 5 / 5 | 三种强调色都受控，主文清楚，成功色只用于完成。深色有明暗层次，Ember 的橙色没有侵占完成语义。未做逐像素 WCAG 数值审计。 |
| 层级与表面 | 4 / 5 | 当前组、输入区域、底部 CTA 一眼可辨；Board 全卡高亮使当前组在卡内的优先级稍弱。 |
| 分组与对齐 | 4 / 5 | 组表、上次记录、已选顺序明确；Board 首屏几乎只显示一个动作，未充分兑现“全计划总览”。 |
| 数据可视化 | 4 / 5 | 全程完成条、Focus 逐组短条、休息倒计时与进度相互配合，没有无关装饰图。完成状态主要依赖 check，常规尺寸的文字状态还可加强。 |
| 平台适配 | 4 / 5 | SwiftUI 字体、原生菜单、44pt 以上主要控件与深色方向合理；窄屏大字改为纵向组卡。数字字段 VoiceOver 名称缺少字段身份；尚无 iOS 键盘、安全区与 VoiceOver 实测。 |
| **合计** | **29 / 35** | **无截图可确认的 P0；有下列 P1。** |

## 必修项（P0）

**未发现。** 检查的实际 PNG 没有文字溢出、关键操作不可见、明暗主题明显失效等一眼可见的硬伤。此结论仅覆盖这些渲染状态，不代表真实设备或完整交互已通过。

## 建议项（P1）

1. **Board 的训练总览不够“总览”。** [Tide Board light](comparisons/tide-board-light.png)、[Graphite Board dark](comparisons/graphite-board-dark.png)、[Ember Board light](comparisons/ember-board-light.png) 中，展开动作从约 266pt 占到 720pt，下一动作只有头部露出。建议默认只显示当前组的 64pt 输入行 + 20pt 已完成摘要 + 44pt“查看全部 4 组”入口，把展开卡控制在约 260–300pt；其他动作保留 64–72pt 折叠卡。完整组表通过明确入口展开。保持数字字段至少 56pt 高，避免单纯压小触控区。这样首屏应至少看到当前动作和两个后续动作。

2. **当前组标签过小，数字输入语义不足。** [Flow 训练 light](shots/tide-flow-workout-light.png) 中“当前”明显弱于其他辅助信息；源码 `WorkoutStudioView.swift:446` 使用固定 10pt。改为可随 Dynamic Type 缩放的 12pt caption，必要时组号列从 40pt 增至 44pt。`numericField`（同文件约 490–495 行）目前只以数值作为可访问性名称，应分别读出“第 3 组，重量，60 千克”和“第 3 组，次数，10”，触控高度从 48pt 增至北极星要求的 56pt；已完成行的字段若不能编辑，应呈现文本而非可聚焦的空动作按钮。

3. **空动作库给了方向，没有给可执行入口。** [空库 dark](shots/tide-flow-picker-dark-emptyLibrary.png) 只说“导入预置动作后”，底部按钮禁用；第一次使用者仍不知道在哪里导入。建议空态增加一个 48–52pt“导入预置动作”按钮，或一个至少 44pt 的“前往动作库设置”原生导航入口。保持空库与无搜索结果分开；[无结果 light](shots/tide-flow-picker-light-noResults.png) 的清除筛选与保留已选流程值得保留。若本轮不提供导入能力，应明确标记此状态只是视觉演示。

4. **Focus 动作卡有较多无效高度。** [Graphite Focus light](comparisons/graphite-focus-light.png)、[Ember Focus dark](comparisons/ember-focus-dark.png) 的动作名称区约 40pt，图标到器械标签之间留下较大空白，首屏只看清四个动作。建议卡片内间距从 12pt 调至 8pt，短动作名不强制占 40pt，整体目标 112–120pt；长名称仍允许自然增高，不加单行截断。保持整卡可点与顺序标记。这能保留探索感，同时减少寻找动作的滚动量。

5. **Graphite 的区别目前主要是颜色和圆角。** 对照 [Graphite Flow dark](comparisons/graphite-flow-dark.png)、[Tide Flow light](comparisons/tide-flow-light.png) 与 [Ember Flow light](comparisons/ember-flow-light.png)：Ember 的 serif 标题、暖色区域和 24pt 轮廓已有独立性；Graphite 的页面密度、标题权重、胶囊筛选仍与 Tide 接近。建议 Graphite 把筛选改为 8–10pt 圆角、表格分隔提高到 1pt、标题改 28pt semibold、常规行维持 64–68pt；保持 Tide 的 18pt 卡片和柔和轮廓，避免只靠蓝/青区分。触控目标不能随“紧凑”缩到 44pt 以下。

6. **键盘、屏幕边界与辅助功能只能标为待 iOS 验证。** [键盘 light](shots/tide-flow-workout-light-keyboard.png) 的当前行、单位、关闭、删除、小数点和完成可见；[休息 dark](shots/tide-flow-workout-dark-resting.png) 有清晰计时、±10 秒和跳过；[撤销 light](shots/tide-flow-workout-light-undo.png) 的撤销独立于主操作。[窄屏大字 picker](shots/tide-flow-picker-light-normal-large-narrow.png) 与 [窄屏大字 workout](shots/tide-flow-workout-light-normal-large-narrow.png) 没有明显水平溢出。不过这些是 macOS `ImageRenderer` 的手机尺寸画面，状态栏、home indicator 和键盘为原型内容，不构成 iOS Simulator 验收。生产迁移需再看 375/393pt、light/dark、accessibility1 下真实安全区及系统键盘，保留至少 16pt 输入到键盘间隔，并检查 VoiceOver 字段顺序。不得将本轮图称为模拟器截图或性能结论。

## 做得好的地方（保留）

- Flow 选择行的名称、肌群/器械、添加标记与已选顺序清楚，连续选两个动作后仍可继续浏览。
- 训练页“上次记录 → 当前数字 → 完成这一组”的阅读顺序稳定；完成与结束训练分开。
- Focus 的 58pt 数字与原位步进操作适合健身房抬眼和单手记录，训练页比其选动作页更成熟。
- Tide 是较均衡的默认方向；Graphite 的黑白 CTA 对频繁记录清楚；Ember 的编辑式标题提供了真正可见的风格差异。
- 休息面板没有同时堆叠第二个竞争性主按钮，撤销也没有遮住当前组。
- 大字状态采用纵向组卡，宁可滚动也不挤小输入；此策略应保留到生产验收。

## 评审边界

本次未运行交互、模拟器、屏幕阅读器、帧率或能耗测量；也没有把合成搜索、编译通过或截图导出当作真实训练性能证明。这里评审的是可见 UI 与少量直接相关的可访问性标注。源码未作任何修改。
