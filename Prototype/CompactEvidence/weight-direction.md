# B：左右重量与器械默认配重

2026-10-16 · my-designer · 原生 SwiftUI / DesignKit · 隔离 Prototype

[公开预览](https://leepepe.github.io/vitalstride/workout-layouts/#weights) · [B 布局与玻璃](b-direction.md)

## 输入入口与口径

- 键盘第二个辅助键显示当前重量方式「合计 / 左右」，展开固定188pt重量面板；More → 当前组 → 重量方式也可进入。复制下组仍在More。
- 合计表示这一组记录的总负荷；左右表示左右两侧分别记录。第一次由合计切左右时平分；奇数最小精度按0.01kg分配，保持合计不变。切回合计相加；不等重两侧在合计未变时可再次恢复。
- 点组表或键盘左／右字段编辑该侧；重量支持两位小数，0–999kg，次数1–999。左→右复制和交换左右为明确动作，会改变相应数值。合计超过999kg时合计模式禁用并说明原因。
- 左右模式也共用一组次数；单侧次数、子组仍属于后续扩展。
- 两侧均纳入容量演示计算；复制下组、保存、放弃草稿支持两侧；空值阻止提交／切换操作对象。被动浏览其他动作仍不更换输入目标。

## 固定器械默认重量

本轮将用户的“默认重量”解释为**常用起始配重**。空载阻力／杆重与加片相加没有在此轮混入；若需要基础重量，可沿独立口径继续设计。

- 固定器械／绳索动作：重量面板 → 设置默认，或More → 当前动作 → 器械默认重量。自由重量和自重不出现这个入口。
- 默认配重按当前动作区分，单位kg、口径为合计。没有默认值时不自动假定；「带入默认」禁用，保留「设置默认」。
- 独立输入表单复用数字区；主按钮变为「保存默认」，关闭按钮为取消。保存只更新默认值，保留本组草稿；不会顺手记组或触发休息。
- 新增组时带入默认；已有组不重写。「带入默认」明确替换当前草稿重量，仍须保存；若是左右模式则按合计分配到两侧。
- More可清除默认。示例45kg为演示值，没有推荐含义；默认值仅存原型会话内存，未跨启动持久化，也不关联真实健身房／实体器械身份。

## 视觉和验收

保留64pt侧栏、连续右侧组表、独立snackbar、玻璃操作层；组行52pt，左右字段各≥44pt。重量面板替换数字区，不增加键盘高度。主题色没有变更。

本轮18张专用截图（8态明暗＋375pt左右输入明暗）另存`weight-shots/`，同步刷新32张B图，保留52张V2历史图。使用macOS ImageRenderer的手机尺寸演示图，非iOS交互、VoiceOver、真实Dynamic Type、原生Liquid Glass光学效果或性能验收。

验证命令：

```bash
swift build --package-path Prototype
swift test --package-path Prototype
swift run --package-path Prototype CompactWorkoutStudio --render-weights Prototype/CompactEvidence/weight-shots
swift run --package-path Prototype CompactWorkoutStudio --render-b Prototype/CompactEvidence/b-shots
```

构建通过，18项状态测试通过（本轮新增4项）。覆盖不等重往返、左右交换／复制、保存／再编辑、两侧容量、无效右侧拦截、0.01kg合计保持、默认保存与本组草稿分离、新组带入、取消／清除及非法默认输入。

独立截图初评30/35，3项P1修正后经6张指定新图独立复核确认解决，保留初评分；完整结果见[本轮评审](weight-review.md)。本轮未改生产App或查询／持久化路径，生产移植继续按仓库PR-required流程单独交付。
