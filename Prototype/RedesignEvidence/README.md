# 动作选择 + 训练页设计交付

**[动作选择与训练画廊 →](index.html)** · **[配套键盘画廊 →](keyboard.html)** · 2026-10-16 · my-designer 主导

已完成 **3 种风格 × 3 种布局 = 9 种组合**。每种组合包含动作选择、训练进行中两页的浅色与深色版本；共 54 张原生 SwiftUI 渲染图、18 张双页对比板，附可运行的原生交互工作室。所有数据均为演示数据。

**数量确认：动作选择页 9 个、训练页 9 个、配套键盘 9 个。** 键盘沿用三种风格，另设全宽数字、拇指侧栏、连续记组三种布局；重量/次数、浅深色及边界状态新增 48 张图、18 张对比板。总交付为 **102 张屏幕图 + 36 张对比板**。键盘详见 [键盘交付与验证](keyboard-delivery.md)。

## 先看这三个方向

| 方向 | 预览 | 建议用途与取舍 |
|---|---|---|
| **推荐：S1 Tide 青蓝 × L1 效率列表** | [浅色](comparisons/tide-flow-light.png) · [深色](comparisons/tide-flow-dark.png) | 常驻搜索、紧凑列表、当前组表格；识别快、滚动少，最适合默认流程 |
| S2 Graphite 石墨 × L2 单手专注 | [浅色](comparisons/graphite-focus-light.png) · [深色](comparisons/graphite-focus-dark.png) | 黑白主操作、大数字和快捷步进；疲劳时更易读，查看全计划需切换 |
| S3 Ember 暖色 × L3 训练总览 | [浅色](comparisons/ember-board-light.png) · [深色](comparisons/ember-board-dark.png) | 暖色、衬线标题、计划折叠卡；品牌辨识和全局查看更强，当前动作占用空间较大 |

风格和布局是独立选择，画廊中可比较其余六种组合。青蓝强调安静和清晰；石墨采用较小圆角、紧凑标题和行距；暖色采用较大圆角与衬线标题。三者都消费 DesignKit 的 Theme token，不引入另一套组件或配色引擎。

## 便捷性与功能性

本轮可执行的核心路径：

- 动作选择：中英文搜索、肌群与器械组合筛选、清除筛选、连续多选/反选、跨筛选保留顺序、已选清单、确认添加、取消，以及空动作库载入演示动作。
- 训练：切换动作、当前组重量/次数编辑、单手步进、添加组、完成/取消完成、休息 ±10 秒与跳过、删除/撤销、手动替换动作、结束确认和总结预览。仅剩一组时不允许删除。
- 阅读与安全：数字输入目标高 56pt，常规按钮不低于 44pt，结束与完成分开；大字环境使用单列与纵向字段布局。非当前数字字段呈现为文字，避免无操作按钮；已完成组同时显示勾和文字。

新增设计提案包括：器械独立筛选、已选顺序队列、当前动作切换器、总览折叠卡及快捷步进。它们不是对当前生产能力的描述。

以下为视觉表示或尚未接入的生产能力：时长和上次记录是固定演示值；容量仅按演示模型计算；手表固定显示未连接。RPE、单侧/子组、kg/lb、渐进建议、AI 替代、生产 UIKit 自定义键盘宿主、动作排序/删除与放弃训练、SwiftData/CloudKit、后台保存、Live Activity、Watch/HealthKit 均未迁入原型。高级菜单与最小化入口显示说明，不伪装成功。

演示从已有四动作训练开始，已选动作确认后追加到当前训练；不重复添加已存在动作。撤销不自动在五秒后过期，保留到用户操作或结束训练。配套键盘打开即全选，重量/次数共享本组草稿；收起保存而不记组，K3 则明确保存并记组。真实产品的保护、撤销生命周期和高级操作必须按 [现有流程审计](workflow-audit.md) 保留，不应从原型行为反推产品合同。

## 性能设计与迁移要求

| 项目 | 本轮实现 / 设计约束 | 生产验收目标，尚未实测 |
|---|---|---|
| 浏览与搜索 | 无动作照片下载、无整页模糊；列表采用单层惰性容器；十条 fixture 即时筛选 | 保留已有 200ms debounce、分组缓存与稳定输入宿主；完整库搜索含防抖 p95 ≤350ms |
| 记组 | 先本地状态反馈，只有休息面板每秒刷新；按结束日期计算剩余时间 | 选择/完成可见反馈 ≤100ms；填好数据后一击记组；历史查询有界、不逐帧查询 |
| 布局 | 稳定底栏；截图模式只为完整导出改为 eager 布局 | 保留现有唯一几何动画所有者，避免 safe-area 尺寸反馈回路与嵌套 Lazy 容器 |
| 滚动与输入 | 不增加后台媒体或网络依赖 | 用 Instruments 检查 60Hz 下 16.7ms 帧预算、animation hitches、主线程与能耗 |

这些是实现原则与建议目标，**没有声称已达到生产 FPS、搜索时延或能耗指标**。完整源码证据、性能历史约束与回归清单见 [workflow-audit.md](workflow-audit.md)。

## 运行与复现

从仓库根目录执行：

```bash
swift run --package-path Prototype WorkoutDesignStudio
```

工作室左侧可分别切换三种页面布局与三种键盘布局，以及风格、浅深色、页面及状态。选择“数字输入”场景可直接体验键盘；英文用 `STUDIO_LANGUAGE=en` 运行。

```bash
swift build --package-path Prototype
swift test --package-path Prototype
swift run --skip-build --package-path Prototype WorkoutDesignStudio --render Prototype/RedesignEvidence/shots
swift run --skip-build --package-path Prototype WorkoutDesignStudio --render-keyboards Prototype/RedesignEvidence/keyboards
python3 Prototype/RedesignEvidence/make_comparisons.py
open Prototype/RedesignEvidence/index.html
```

配对脚本使用 Pillow；原型不新增任何第三方 Swift 依赖。画廊直接打开即可，不需要服务器、账户或网络。

## 验证记录与边界

- Swift 6 `swift build` 成功；**8 个 Swift Testing 行为测试通过**。原四项页面流程加上草稿切换与保存、输入校验及取消、快捷操作和单次记组、稳定目标 ID 与末尾复制四项键盘流程。
- 页面 **54 张 PNG + 18 张比较板**；键盘 **48 张 PNG + 18 张比较板**，包含休息、撤销、无效输入及三种键盘的 375pt 大字回退。各自的核心九种组合都有浅深色。
- 169 个 key 的中英 catalog 覆盖与静态引用通过检查；页面与键盘均额外导出英文版本至临时目录并抽查，具体数量见键盘交付记录。
- 画廊脚本通过 DOM 桩验证全部 24 种主题/页面/风格筛选组合，共检查 600 个生成图片链接；本地图片、说明和评审链接完整。此为脚本与文件检查，未声称浏览器点击通过。
- 页面独立视觉评审 **31/35，无截图可确认的 P0**；完成文字和结束页状态经收尾复核已解决。见 [页面最终评审](design-review.md)；第一轮 29/35 记录在 [第一轮评审](design-review-round1.md)。键盘独立评分 **30/35，无未解决的截图 P0**，见 [键盘独立评审](keyboard-review.md)。
- `swiftlint` 本机未安装，未执行。未运行生产 App 的 xcodebuild，也没有改动生产页面、数据模型或发布配置。
- 图片来自 **macOS ImageRenderer，393×852pt、2×**；375pt 图验证布局回退。macOS 字体行为与 iOS 不同，大字图不代表 iOS 全档 Dynamic Type 已通过；状态栏、home indicator 与数字键盘为原型内容。
- UI 自动化工具拒绝访问 WorkoutDesignStudio，浏览器工具也不可用；原生点击、离线画廊的浏览器交互尚未实测。行为证据来自状态模型测试；截图证据来自实际原生渲染与独立评审。
- 最终迁入生产前，须完成 iPhone Simulator 的 light/dark、安全区、键盘 × none/rest/undo 六态、375/393pt、Dynamic Type 和 VoiceOver 验收；触觉、后台、传感器及真实能耗另测。

本轮在隔离的 `Prototype` layer 内完成，使用 DesignKit，未读取真实训练或健康数据。它是完整可比较的设计交付，尚未迁入生产 App。

基线：`550f4bf611ef16ea15c28dc90d858ca71673abf2`

分支：`agent/design/workout-explorations-20261016`

相关材料：[设计目标](north-star.md) · [现有功能与性能审计](workflow-audit.md) · [页面最终视觉评审](design-review.md) · [键盘交付](keyboard-delivery.md)
