# 动作选择与训练页：现有流程审计

2026-10-16 · 源码基线 `550f4bf611ef16ea15c28dc90d858ca71673abf2` · my-designer 的只读审计切片。

本报告审计生产页面与相关子视图，供隔离的 Native SwiftUI / DesignKit 原型保留产品能力。
没有修改生产源码，没有执行构建、测试、Instruments 或真机性能测量。
以下“已有”来自源码；历史性能故障来自源码注释；UX 风险是待截图验证的判断；
所有延迟、帧率及操作数目标均为建议验收值，不是已达成结果。

原型只依赖 DesignKit，使用明确标注的演示数据；不访问 SwiftData、HealthKit、网络或生产训练记录。
约束来源：`Prototype/CONTEXT.md:4`；`.specify/memory/constitution.md:9`、`:25`、`:227`、`:229`。

## 已有能力：生产迁移必须保留

### 动作选择

| 能力 | 已有语义 | 精确源码引用 |
|---|---|---|
| 单选 / 多选 | 单选点击即返回；多选可反选，确认按点击顺序返回；未选择时禁用确认；支持取消 | `VitalStride/Sources/ExercisePickerView.swift:68`、`:141`、`:241`、`:1072` |
| 搜索 | 英文与中文名称不区分大小写匹配；去首尾空格；200ms 防抖 | `VitalStride/Sources/ExercisePickerSectionGrouping.swift:10`；`VitalStride/Sources/ExercisePickerView.swift:70`、`:231` |
| 肌群筛选 | “全部”或一个肌群，与搜索叠加；不是多个肌群的复选 | `VitalStride/Sources/ExercisePickerView.swift:477`；`VitalStride/Sources/ExercisePickerSectionGrouping.swift:16` |
| 器械分类 | 按器械 section 分组、数量、侧边分区跳转与拖动索引；现有页面并非独立器械筛选器 | `VitalStride/Sources/ExercisePickerSectionGrouping.swift:30`；`VitalStride/Sources/ExercisePickerView.swift:767`、`:1042` |
| 滚动上下文 | 肌群变化尽量保留原器械锚点；搜索变化回到首个结果分区；索引跟随可见分区 | `VitalStride/Sources/ExercisePickerView.swift:189`、`:209`、`:701` |
| 输入与空状态 | 空动作库、零搜索结果、空肌群分别表达；零结果仍保留搜索焦点；取消、清除、用户拖动可主动收键盘 | `VitalStride/Sources/ExercisePickerView.swift:119`、`:448`、`:623`、`:692`、`:1020` |
| 信息边界 | 卡片当前有器械图标、动作名称、肌肉标签；没有真实照片、缩略图或演示视频 | `VitalStride/Sources/ExercisePickerView.swift:1291`、`:1362` |

### 进行中的训练

| 能力 | 已有语义 | 精确源码引用 |
|---|---|---|
| 训练级操作 | 批量添加动作、多个动作时调整顺序、大字模式、结束与放弃二次确认 | `VitalStride/Sources/ActiveWorkoutView.swift:152`、`:204`、`:254`、`:268`、`:854` |
| 动作级操作 | 添加组、手动替换、AI 替代、AI 不适用时手动回退且预选原肌群、删除动作及组数据的确认 | `VitalStride/Sources/ActiveWorkoutView.swift:211`、`:216`、`:246`；`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:188`、`:237`、`:336` |
| 主要输入 | kg/lb 显示转换、重量 × 次数、单侧左 / 右重量、组类型、完成 / 取消完成 | `VitalStride/Sources/ActiveWorkout/SetRow.swift:208`、`:224`、`:307`、`:526`、`:891` |
| RPE | 非热身主组支持 6–10 或未设置；当前藏于组设置菜单 | `VitalStride/Sources/ActiveWorkout/SetRow.swift:318` |
| 历史与建议 | 上次同动作同序号主组记录，无历史时不占位；智能渐进建议可点击填充；填充后编辑与完成有接受状态语义 | `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:288`；`VitalStride/Sources/ActiveWorkout/SetRow.swift:173`、`:532`、`:581`、`:645`、`:775` |
| 自定义数字键盘 | 聚焦选中已有文本；重量十进制 / 次数整数；递增、递减、单侧、复制到下一组；三档次数预设；完成收键盘 | `VitalStride/Sources/SelectAllTextField.swift:130`、`:156`；`VitalStride/Sources/WorkoutNumericKeyboard.swift:54`；`VitalStride/Sources/ActiveWorkout/SetRow.swift:848` |
| 新增组与复制 | 添加主组继承最后一个主组的输入 / 类型 / 单侧语义；复制覆盖下一行，下一行可能是子组；末尾才追加 | `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:301`、`:483` |
| 子组 | 递减默认父组重量 ×0.85，递增 ×1.15；继承次数 / 单侧；子组重量、次数、类型、RPE 当前只读，可完成及删除 | `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:365`；`VitalStride/Sources/ActiveWorkout/SubSetRow.swift:1`、`:119` |
| 删除安全 | 最后一组保护由领域层裁定；主组带子组时先确认连带删除；行菜单和滑动删除同一路径 | `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:248`、`:401`、`:418` |
| 撤销 | 最近一次删除有 5 秒撤销；新删除替换旧撤销；撤销优先于休息提示，休息并未暂停 | `VitalStride/Sources/ActiveWorkout/SetDeletionUndoController.swift:21`、`:37`、`:90` |
| 撤销生命周期 | 删除所属动作、结束或放弃训练时清除不能再履行的撤销；删除后移动 VoiceOver 焦点并播报 | `VitalStride/Sources/ActiveWorkoutView.swift:350`、`:1231`、`:1248`、`:1287`；`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:438` |
| 休息 | 完成组触发休息；±10 秒、跳过、完成提示；后台 / 锁屏 Live Activity 属已有产品流程 | `VitalStride/Sources/ActiveWorkoutView.swift:748`、`:798`、`:832`；`specs/000-baseline-existing-codebase/spec.md:64` |
| 状态信息 | 时长、组数进度、容量；大字模式持久化；应用进入后台保存 | `VitalStride/Sources/ActiveWorkoutView.swift:73`、`:360`、`:389` |
| 实时心率 | 未连接 / 等待采样 / 真实数值三态；重新连接等待新样本；采样时间过期 20 秒回等待；不能制造数值 | `VitalStride/Sources/ActiveWorkoutView.swift:903`、`:954`、`:1310`、`:1344` |

## 当前 UX 风险

1. **卡片信息密度低**：内容最小高度 118pt，另加 padding；只有图标、名称和肌肉标签。
   两行名称在窄卡片内仍可能截断；侧边索引一直预留 48pt，进一步压缩横向空间。
   证据：`VitalStride/Sources/ExercisePickerView.swift:587`、`:1323`、`:1333`。
2. **跨筛选核对不方便**：当前多选只显示添加数量，没有选中项汇总或顺序检查区。
   已选抽屉、选中顺序徽标是新表现方案。证据：`VitalStride/Sources/ExercisePickerView.swift:241`、`:1082`。
3. **搜索发现性和视口竞争**：搜索默认缩成右下角按钮，搜索与肌群是两个浮层；打开键盘后可用结果区继续缩小。
   常显搜索或统一筛选区值得比较。证据：`VitalStride/Sources/ExercisePickerView.swift:298`、`:381`。
4. **训练标题与操作争空间**：动作标题仅一行，旁边是添加一组及菜单；长名称容易压缩。
   证据：`VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:172`。
5. **主任务与辅助信息混杂**：每组可能有输入、组类型、设置、完成、历史提示、渐进建议；
   高级操作又分散在动作菜单、组菜单、键盘三处。设计需要让当前组优先，并保持高级能力可发现。
   证据：`VitalStride/Sources/ActiveWorkout/SetRow.swift:166`、`:293`、`:848`。

以上不是已报告的新生产 bug，也没有替代真实截图评审。

## 性能与布局稳定性：已有约束

| 约束 | 源码证据与含义 |
|---|---|
| 搜索防抖与缓存 | `VitalStride/Sources/ExercisePickerView.swift:70`、`:182`、`:231`：保留 200ms debounce 和缓存分组；不要逐键重扫完整库 |
| 一层懒布局 | `VitalStride/Sources/ExercisePickerView.swift:654`：现有 eager 分区 VStack + LazyVGrid；源码注释记录嵌套 LazyVStack / LazyVGrid 曾出现主线程 100% CPU；此为历史说明，非本次测量 |
| 避免尺寸反馈回路 | `VitalStride/Sources/ExercisePickerView.swift:57`、`:1192`：iOS 18 使用 overlay + 静态 scroll margin，iOS 26 使用 safeAreaBar；不要重建由浮层与网格互相决定高度的 inset 回路 |
| 输入宿主稳定 | `VitalStride/Sources/ExercisePickerView.swift:340`、`:623`：结果重算、query 更新和零结果不能销毁 TextField / ScrollView，防止键盘意外消失 |
| 索引不堆动画 | `VitalStride/Sources/ExercisePickerView.swift:587`、`:779`、`:1379`：拖动即时跳转，避免逐帧堆滚动动画；索引出现 / 消失不能导致列宽重排 |
| 局部计时刷新 | `VitalStride/Sources/ActiveWorkoutView.swift:509`：1Hz 计时只包时间格式化，不在每秒 tick 中重算整页组数、容量、历史 |
| 行上下文单遍计算 | `VitalStride/Sources/ActiveWorkout/ActiveExerciseSection.swift:53`：排序后 O(n) 单遍生成编号等上下文；不要恢复每行重复排序 / 扫描 |
| 历史查询有界 | `VitalStride/Sources/PreviousSetLookup.swift:15`、`:35`：每次查询最多 50 次训练；当前主组分别调用查询，重设计不能增加每帧历史读取。是否统一缓存需后续生产实现评估 |
| 026 动画合同 | `VitalStride/Sources/ActiveWorkoutView.swift:97`；`VitalStride/Sources/ActiveWorkout/ActiveWorkoutSnackbarLayout.swift:58`：当前源码已使用稳定底部结构、唯一根部几何动画所有者、无子级几何动画或插入 / 删除 transition |
| 键盘与提示不遮挡 | `specs/026-active-workout-animation-policy/spec.md:25`、`:55`、`:74`：键盘隐藏 / 显示 × none / rest / undo 六态，compact / Large Mode 共用策略；最终一组可滚出；只允许一个可交互、可访问的提示；保留焦点路由 |

026 spec 文案仍标为 planning review candidate，但本 checkout 的生产源码已经体现该策略。
此报告不据 spec 状态推断 PR、CI 或交付状态。

## 三种布局的评估方向

主设计定义的 L1 / L2 / L3 以 `north-star.md` 为准；以下是流程层面的比较依据，均为提案。

| 布局 | 流程价值 | 应验证的取舍 |
|---|---|---|
| L1 Flow / 效率列表 | 常显搜索、紧凑动作行；训练输入与上次记录对齐，完成操作清晰 | 快速扫读、少滚动；避免表格密度压缩触控目标 |
| L2 Focus / 单手专注 | 探索卡片与选择顺序；当前动作 / 当前组大输入区，步进操作 | 疲劳时读数与单手命中；仍能主动查看和切换整个计划 |
| L3 Board / 训练总览 | 可见分类、动作列表；计划折叠卡中展开当前动作 | 多动作切换和整体进度；窄屏列宽、展开后的键盘空间 |

**新增提案与已有能力须区分**：独立器械筛选、选中队列 / 顺序徽标、当前动作切换器、
折叠训练卡、步进输入和新的主操作位置属于本轮交互呈现提案，不能声称当前生产页已具备。
收藏、最近使用、自动跳下一组、超级组、动作媒体和训练暂停未在本次目标源码审计中得到证明；
如后续展示，必须明确写为新提案并另行确认产品范围。

## 建议验收场景与指标

### 已有合同的回归场景

- 搜索 `bench` / 中文动作名称，跨肌群切换，已选不丢；零结果继续打字，无意外收键盘。
- 多选三动作并反选一个，确认顺序与用户选择顺序一致；取消不改调用页面。
- 无历史训练、长中英动作名称、kg / lb、单侧输入、热身 / 工作 / 递增 / 递减组。
- 休息中删组 → 5 秒内撤销；期间休息继续；主组携带子组删除先确认。
- 键盘隐藏 / 显示 × none / rest / undo 六态，且覆盖 compact / Large Mode、长撤销文案和最终一行。
- VoiceOver 只读到当前可用提示，删除后焦点合理；不重叠的 ≥44×44pt 目标；Dynamic Type 不靠缩字挤入。
- light / dark、375pt 窄屏、393pt 标准屏；未连接 / 等待 / 实时心率三态，不制造缺失数据。
- 结束训练和放弃训练独立且确认；真实数据失败呈现错误或回退入口，不替换为演示数据。

### 建议测量值：尚未实测

| 建议目标 | 测量方式与限制 |
|---|---|
| 搜索最后一次输入后 ≤350ms 更新结果 | 完整生产动作库；包含现有 200ms debounce；记录设备、库大小、冷 / 热状态和 p50 / p95 |
| 选择 / 完成的可见确认 ≤100ms | 主线程交互时间戳或屏幕录制；不能把网络或持久化放到反馈前阻塞 |
| 滚动与键盘开合按 60Hz 的 16.7ms 帧预算检查 | Instruments 的 animation hitches / 主线程记录；原型导出速度不能证明实际帧率或能耗 |
| 填好数据后完成一组只需一次点击 | 人工操作计数，包含键盘显示时的可达性；任何自动跳转须单独列为提案 |
| 选择三动作后一次确认 | 不含打开入口，共 3 次选择 + 1 次确认；需要先展开搜索时另外记录动作数 |

本轮可交付构建、渲染、可点击演示与合成数据行为；生产性能、触觉、传感器、后台唤醒、
持久化可靠性、Watch 通信需要对应运行环境的独立证据。
纯视觉最终移植的默认门是 iPhone Simulator light / dark 截图或 SnapshotTesting，
不是必须具备真机：`.specify/memory/constitution.md:229`。

## 原型交付时必须披露的未演示高级能力

以实际原型可执行路径为准。凡没有实现并验证的下列能力，均应在交付说明写明“生产已有，本轮未演示 / 未接入”，
不能因画了入口、用了 demo 数字或通过静态截图就声称覆盖。

1. 原生自定义数字键盘的选中替换、整数 / 小数解析、三档预设、复制覆盖下一行、单侧切换及子组创建。
2. RPE、上次同序号主组查询、智能渐进建议填充与接受 / 覆盖状态。
3. 子组树结构、最后一组保护、主组连带删除确认、完整 5 秒撤销与 VoiceOver 焦点迁移。
4. AI 替代的 loading / error / recommendation，以及手动回退且保留原肌群。
5. 真正的 SwiftData 保存、恢复、训练排序持久化、CloudKit 同步、结束 / 放弃对实际记录的影响。
6. Watch 实时心率、断连 / 重连 / 过期语义、HealthKit 授权、真实单位与训练容量计算。
7. 真实时间驱动的后台 / 锁屏休息、Live Activity、触觉和通知；演示倒计时不能证明后台可用。
8. 生产 UIKit 键盘与 snackbar 六态、原生 VoiceOver、全部 Dynamic Type 档位、窄屏和 iOS 18 / 26 回退路径。

原型验证报告应把“已演示交互”“仅视觉表示”“未演示的生产高级能力”“新增提案”分开列出，
并注明任何手机尺寸 macOS 渲染图与真正 iOS Simulator 截图的来源差异。
