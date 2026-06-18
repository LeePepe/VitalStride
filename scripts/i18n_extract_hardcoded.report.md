# Hardcoded Chinese String Baseline

Total findings: 410

Excludes comments, test files, debug `print`/`debugPrint`, and `String(localized:)` source keys.

## `Packages/VitalModels/Sources/VitalModels/Enums/Equipment.swift`

- Line 13: `杠铃` -> `localized_45d14937`
- Line 14: `哑铃` -> `localized_2f97f023`
- Line 15: `固定器械` -> `g_d_q_u68b0`
- Line 16: `自重` -> `z_u91cd`
- Line 17: `绳索` -> `localized_f39ca3d9`
- Line 18: `壶铃` -> `localized_c5619618`

## `Packages/VitalModels/Sources/VitalModels/Enums/MuscleGroup.swift`

- Line 14: `胸` -> `localized_e888ab28`
- Line 15: `背` -> `b`
- Line 16: `肩` -> `localized_f6f6813c`
- Line 17: `腿` -> `t`
- Line 18: `臂` -> `localized_d2d91b4f`
- Line 19: `核心` -> `localized_67255012`
- Line 20: `全身` -> `q_s`

## `Packages/VitalModels/Sources/VitalModels/Enums/MuscleTranslation.swift`

- Line 5: `内收肌群` -> `n_s_j_u7fa4`
- Line 6: `三角肌前束` -> `localized_c07308bf`
- Line 7: `肱二头肌` -> `localized_71f8bfc3`
- Line 8: `肱肌` -> `localized_02be2612`
- Line 9: `肱桡肌` -> `localized_bfb889b6`
- Line 10: `小腿` -> `x_t`
- Line 11: `核心肌群` -> `localized_24ef3a8c`
- Line 12: `竖脊肌` -> `localized_1f010bae`
- Line 13: `前臂` -> `q_u81c2`
- Line 14: `臀肌` -> `localized_ff08b3fc`
- Line 15: `臀中肌` -> `localized_f65a80cd`
- Line 16: `臀小肌` -> `localized_d4e0ca15`
- Line 17: `腘绳肌` -> `localized_173d56f7`
- Line 18: `髋屈肌` -> `localized_1624f366`
- Line 19: `冈下肌` -> `localized_f352a1ce`
- Line 20: `三角肌中束` -> `localized_27acfb38`
- Line 21: `背阔肌` -> `b_u9614_j`
- Line 22: `胸大肌下部` -> `localized_01455328`
- Line 23: `下斜方肌` -> `x_u659c_f_j`
- Line 24: `腹斜肌` -> `localized_1db5c094`
- Line 25: `胸大肌` -> `localized_86300c85`
- Line 26: `股四头肌` -> `localized_78edeafa`
- Line 27: `三角肌后束` -> `localized_766453b9`
- Line 28: `腹直肌` -> `localized_77787ffd`
- Line 29: `菱形肌` -> `localized_867d35b4`
- Line 30: `前锯肌` -> `q_u952f_j`
- Line 31: `胫骨前肌` -> `localized_c1be3b23`
- Line 32: `腹横肌` -> `localized_d371c414`
- Line 33: `斜方肌` -> `localized_15d5ecbe`
- Line 34: `肱三头肌` -> `localized_1241e967`
- Line 35: `胸大肌上部` -> `localized_ffe85fa9`
- Line 36: `上斜方肌` -> `s_u659c_f_j`

## `Packages/VitalModels/Sources/VitalModels/Enums/SetType.swift`

- Line 11: `正式` -> `z_s`
- Line 12: `热身` -> `r_s`
- Line 13: `递减` -> `localized_0a1766e7`
- Line 14: `递增` -> `localized_3c3d3fb0`

## `VitalStride/Sources/AIAnalysisPrompts.swift`

- Line 15: `对比上次分析结果和当前数据，用一句话概括最显著的变化，不超过 30 字，作为 headline 字段返回。如果没有明显变化或没有上次分析结果，headline 返回 null。` -> `d_b_s_c_f_u6790_u7ed3_u679c_h_d_q_data_y_u4e00_u53e5_h_u6982_u62ec_z_x_u8457_d_b`
- Line 22: `一句话概括最显著的变化(可为null)` -> `localized_e3171f70`
- Line 25: `唯一标识` -> `localized_1cf1366a`
- Line 25: `标题` -> `b_u9898`
- Line 25: `正文` -> `z_w`
- Line 25: `建议(可选,可为null)` -> `localized_4804b3e4`
- Line 25: `SF Symbol名称(可选,可为null)` -> `sf_symbol_name_k_x_k_w_null`
- Line 38: `标签` -> `b_q`
- Line 39: `名称` -> `name`
- Line 39: `值` -> `z`
- Line 58: `今日步数：\(steps)` -> `today_steps_s_value`
- Line 61: `今日活动能量：\(String(format: ` -> `today_h_d_n_l_string_format`
- Line 64: `静息心率：\(hr) bpm` -> `localized_39883023`
- Line 67: `昨晚睡眠：\(String(format: ` -> `localized_6f4ddc98`
- Line 67: `, sleep)) 小时` -> `sleep_x_s`
- Line 70: `最新体重：\(String(format: ` -> `z_x_t_u91cd_string_format`
- Line 72: `近期训练次数：\(context.recentWorkoutCount)` -> `j_u671f_training_reps_value`
- Line 76: `\($0.key) \($0.value)次` -> `value_value_c`
- Line 78: `肌群训练分布：\(groups)` -> `j_u7fa4_training_f_b_value`
- Line 82: `暂无健康数据。` -> `z_none_j_u5eb7_data`
- Line 85: `以下是我的健康和运动数据：\n\(userData)` -> `localized_b8278a14`
- Line 94: `\n\n---\n上次分析结果（仅供对比参考）：\n\(summary)\n---` -> `n_n_n_s_c_f_u6790_u7ed3_u679c_u4ec5_u4f9b_d_b_c_u8003_n_value_n`
- Line 97: `\n\n请生成洞察卡片。` -> `n_n_q_u751f_c_u6d1e_u5bdf_k_p`
- Line 115: `推荐标题` -> `localized_1f7428e0`
- Line 115: `肌群1` -> `j_u7fa4_1`
- Line 115: `肌群2` -> `j_u7fa4_2`
- Line 115: `动作1` -> `d_u4f5c_1`
- Line 115: `动作2` -> `d_u4f5c_2`
- Line 115: `动作3` -> `d_u4f5c_3`
- Line 115: `推荐理由` -> `localized_0fe520aa`
- Line 129: `距上次训练：\(days) 天` -> `j_s_c_training_value_t`
- Line 131: `近期无训练记录` -> `j_u671f_none_training_record`
- Line 137: `\($0.key) \($0.value)次` -> `value_value_c`
- Line 139: `近期肌群训练频率：\(groups)` -> `j_u671f_j_u7fa4_training_p_l_value`
- Line 143: `M月d日` -> `m_month_d_r`
- Line 150: `训练\(index + 1)（\(dateStr)，\(workout.durationMinutes)分钟，\(muscles)）：\(exercises)` -> `training_value_value_value_f_z_value_value`
- Line 158: `以下是我最近的训练情况：\n\(userData)\n\n请推荐今日训练计划。` -> `localized_ae74df7b`
- Line 184: `数据摘要` -> `data_u6458_y`
- Line 184: `建议(可选,可为null)` -> `localized_4804b3e4`
- Line 197: `数据类型：\(context.sampleType)` -> `data_l_x_value`
- Line 198: `数据点数量：\(context.dataPointCount)` -> `data_d_s_l_value`
- Line 199: `时间范围：\(context.timeRangeDescription)` -> `time_u8303_w_value`
- Line 203: `平均值：\(String(format: ` -> `localized_571ca5db`
- Line 206: `最小值：\(String(format: ` -> `z_x_z_string_format`
- Line 209: `最大值：\(String(format: ` -> `z_d_z_string_format`
- Line 212: `最新值：\(String(format: ` -> `z_x_z_string_format`
- Line 219: `以下是我的健康数据统计：\n\(userData)\n\n请分析数据趋势。` -> `localized_12c2718d`
- Line 229: `数据摘要` -> `data_u6458_y`
- Line 229: `建议(可选,可为null)` -> `localized_4804b3e4`
- Line 329: `数据类型：\(context.sampleType)` -> `data_l_x_value`
- Line 330: `数据点数量：\(context.dataPointCount)` -> `data_d_s_l_value`
- Line 331: `时间范围：\(context.timeRangeDescription)` -> `time_u8303_w_value`
- Line 335: `平均值：\(String(format: ` -> `localized_571ca5db`
- Line 338: `最小值：\(String(format: ` -> `z_x_z_string_format`
- Line 341: `最大值：\(String(format: ` -> `z_d_z_string_format`
- Line 344: `最新值：\(String(format: ` -> `z_x_z_string_format`
- Line 348: `以下是我的健康数据统计：\n\(userData)\n\n请分析数据趋势。` -> `localized_12c2718d`
- Line 384: `使用中文` -> `localized_c4b00eb6`
- Line 386: `使用中文` -> `localized_c4b00eb6`

## `VitalStride/Sources/AIAnalysisService.swift`

- Line 232: `训练建议` -> `training_u5efa_u8bae`
- Line 235: `暂时无法生成训练建议，请稍后重试。` -> `z_s_none_f_u751f_c_training_u5efa_u8bae_q_u7a0d_u540e_u91cd_u8bd5`
- Line 283: `暂时无法分析数据趋势，请稍后重试。` -> `z_s_none_f_f_u6790_data_u8d8b_u52bf_q_u7a0d_u540e_u91cd_u8bd5`

## `VitalStride/Sources/AIPromptBuilder.swift`

- Line 70: `以下是用户本周的力量训练数据：\n\n` -> `localized_ce073148`
- Line 73: `本周暂无训练记录。\n` -> `b_week_z_none_training_record_n`
- Line 76: `M月d日 HH:mm` -> `m_month_d_r_hh_mm`
- Line 83: `，时长 \(minutes) 分钟` -> `s_c_value_f_z`
- Line 85: `训练 \(index + 1)（\(dateStr)\(duration)）：\n` -> `training_value_value_value_n`
- Line 99: `  总训练量：\(String(format: ` -> `z_training_l_string_format`
- Line 102: `本周训练次数：\(context.workouts.count)\n` -> `b_week_training_reps_value_n`
- Line 107: `你是一个专业的力量训练教练和运动科学顾问。请基于用户的训练数据，给出简洁、有针对性的训练总结和建议。使用中文回复，控制在 300 字以内。` -> `localized_f4266fbb`
- Line 112: `\(dataSummary)\n请总结我本周的训练情况，包括训练频率、肌群覆盖、训练量趋势，并给出简短建议。` -> `value_n_q_z_u7ed3_w_b_week_d_training_u60c5_u51b5_b_u62ec_training_p_l_j_u7fa4_u`
- Line 119: `以下是用户最近的训练和健康数据：\n\n` -> `localized_932f294d`
- Line 121: `【训练频率】\n` -> `training_p_l_n`
- Line 123: `近期无训练记录。\n` -> `j_u671f_none_training_record_n`
- Line 127: `  - \(group)：\(count) 次\n` -> `value_value_c_n`
- Line 132: `M月d日` -> `m_month_d_r`
- Line 133: `最近一次训练：\(formatter.string(from: lastWorkout.startDate))\n` -> `z_j_u4e00_c_training_value_n`
- Line 137: `\n【健康数据】\n` -> `n_j_u5eb7_data_n`
- Line 139: `  - 平均心率：\(hr) bpm\n` -> `localized_ad7c1aac`
- Line 144: `  - 昨晚睡眠：\(hours)小时\(minutes)分钟\n` -> `localized_e313c35e`
- Line 147: `  - 今日步数：\(steps)\n` -> `today_steps_s_value_n`
- Line 150: `  - 体重：\(String(format: ` -> `t_u91cd_string_format`
- Line 155: `你是一个专业的运动恢复顾问。请基于用户的训练频率和健康数据，评估恢复状态并给出具体建议。使用中文回复，控制在 300 字以内。` -> `localized_2c4dd3cb`
- Line 160: `\(dataSummary)\n请评估我的恢复状态，判断是否存在过度训练风险，并给出恢复建议（包括休息、营养、睡眠等方面）。` -> `value_n_q_u8bc4_u4f30_w_d_recovery_z_t_u5224_u65ad_u662f_u5426_c_z_u8fc7_u5ea6_t`
- Line 167: `以下是用户的历史训练记录，请帮我检测个人记录（PR）：\n\n` -> `localized_863d4fa7`
- Line 170: `暂无训练记录。\n` -> `z_none_training_record_n`
- Line 175: `暂无足够数据检测 PR。\n` -> `z_none_u8db3_u591f_data_j_u6d4b_pr_n`
- Line 179: `  最大重量：\(String(format: ` -> `z_d_weight_string_format`
- Line 180: `  最大单组容量：\(String(format: ` -> `z_d_d_z_r_l_string_format`
- Line 181: `  记录数据条数：\(pr.totalSets) 组\n\n` -> `record_data_u6761_s_value_z_n_n`
- Line 188: `你是一个专业的力量训练教练。请基于用户的历史训练数据，识别个人记录（PR），并给予鼓励和建议。使用中文回复，控制在 300 字以内。` -> `localized_3bc80b47`
- Line 193: `\(dataSummary)\n请分析我的个人记录情况，指出哪些动作有突破，并给出进一步提升的建议。` -> `value_n_q_f_u6790_w_d_u4e2a_u4eba_record_u60c5_u51b5_z_u51fa_u54ea_x_d_u4f5c_y_u`
- Line 200: `你是 VitalStride 的 AI 训练助手，帮助用户分析训练数据和健康状况。\n\n` -> `localized_378f041c`
- Line 201: `【用户近期数据摘要】\n` -> `y_u6237_j_u671f_data_u6458_y_n`
- Line 204: `近期训练 \(context.workouts.count) 次。\n` -> `j_u671f_training_value_c_n`
- Line 208: `\($0.key) \($0.value)次` -> `value_value_c`
- Line 210: `肌群分布：\(groupSummary)。\n` -> `j_u7fa4_f_b_value_n`
- Line 213: `近期无训练记录。\n` -> `j_u671f_none_training_record_n`
- Line 217: `平均心率：\(hr) bpm。\n` -> `localized_d7040852`
- Line 221: `昨晚睡眠：\(hours) 小时。\n` -> `localized_acedeea5`
- Line 224: `体重：\(String(format: ` -> `t_u91cd_string_format`
- Line 227: `\n请使用中文回复，结合上述数据给出个性化建议。` -> `n_q_u4f7f_y_z_w_h_f_u7ed3_u5408_s_u8ff0_data_u7ed9_u51fa_u4e2a_x_h_u5efa_u8bae`

## `VitalStride/Sources/AIQuickAnalysisCard.swift`

- Line 234: `你在卧推上达到了新的个人记录！80kg × 5 是一个很好的突破。建议继续保持当前的渐进超负荷策略。` -> `localized_c3628db1`
- Line 244: `网络请求失败，请检查网络连接。` -> `localized_f1f0ad72`

## `VitalStride/Sources/AISettingsSection.swift`

- Line 72: `智谱 AI` -> `localized_31b5100a`
- Line 170: `AI 设置` -> `ai_settings`

## `VitalStride/Sources/AITrainingAdviceCard.swift`

- Line 490: `建议今天练背部，已休息 2 天` -> `localized_8db1df8e`
- Line 492: `引体向上` -> `y_t_u5411_s`
- Line 492: `杠铃划船` -> `localized_0b3d83d7`
- Line 492: `坐姿绳索划船` -> `localized_b056a66a`
- Line 493: `你已经连续 2 天没有训练背部，背部肌群已充分恢复。配合臂部训练可以提高整体效率。` -> `localized_4c1d7483`
- Line 508: `建议今天练背部，已休息 2 天` -> `localized_8db1df8e`
- Line 510: `引体向上` -> `y_t_u5411_s`
- Line 510: `杠铃划船` -> `localized_0b3d83d7`
- Line 510: `坐姿绳索划船` -> `localized_b056a66a`
- Line 511: `你已经连续 2 天没有训练背部，背部肌群已充分恢复。配合臂部训练可以提高整体效率。` -> `localized_4c1d7483`
- Line 524: `暂时无法生成训练建议，请稍后重试。` -> `z_s_none_f_u751f_c_training_u5efa_u8bae_q_u7a0d_u540e_u91cd_u8bd5`

## `VitalStride/Sources/ActiveWorkoutView.swift`

- Line 55: `训练中` -> `training_z`
- Line 59: `放弃` -> `localized_40c14153`
- Line 64: `结束训练` -> `localized_a5098017`
- Line 82: `完成训练？` -> `done_training`
- Line 83: `完成` -> `done`
- Line 84: `取消` -> `cancel`
- Line 86: `训练将被保存到历史记录` -> `training_j_u88ab_save_d_l_u53f2_record`
- Line 88: `放弃训练？` -> `localized_67177900`
- Line 89: `放弃` -> `localized_40c14153`
- Line 90: `继续训练` -> `localized_5836e523`
- Line 92: `训练数据将不会保存` -> `training_data_j_b_h_save`
- Line 138: `\(exerciseCount) 动作 · \(setCount) 组 · \(volumeText) \(weightUnit.rawValue)` -> `value_d_u4f5c_value_z_value_value`
- Line 177: `训练时长` -> `training_s_c`
- Line 307: `添加第一个动作` -> `add_u7b2c_u4e00_u4e2a_d_u4f5c`
- Line 309: `点击下方按钮选择训练动作` -> `d_u51fb_x_f_a_u94ae_select_training_d_u4f5c`
- Line 351: `添加动作` -> `add_d_u4f5c`
- Line 509: `删除` -> `delete`
- Line 534: `删除` -> `delete`
- Line 543: `动作` -> `d_u4f5c`
- Line 630: `添加一组` -> `add_u4e00_z`
- Line 636: `添加一组` -> `add_u4e00_z`
- Line 637: `在列表末尾插入新的一组` -> `z_l_b_u672b_u5c3e_u63d2_u5165_x_d_u4e00_z`
- Line 720: `次数` -> `reps`
- Line 726: `第 \(index + 1) 组次数` -> `localized_738be03c`
- Line 727: `输入次数` -> `s_u5165_reps`
- Line 782: `第 \(index + 1) 组重量` -> `localized_9fd5ce57`
- Line 783: `输入重量数值` -> `s_u5165_weight_s_z`
- Line 794: `次数` -> `reps`
- Line 799: `第 \(index + 1) 组次数` -> `localized_738be03c`
- Line 800: `输入次数` -> `s_u5165_reps`
- Line 904: `第 \(index + 1) 组，\(exerciseSet.isCompleted ? ` -> `localized_f545cee3`
- Line 905: `双击切换完成状态` -> `s_u51fb_q_h_done_z_t`
- Line 982: `次数` -> `reps`
- Line 988: `第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组次数` -> `localized_b52953f4`
- Line 989: `输入次数` -> `s_u5165_reps`
- Line 1048: `第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组重量` -> `localized_5cb75435`
- Line 1049: `输入重量数值` -> `s_u5165_weight_s_z`
- Line 1061: `次数` -> `reps`
- Line 1067: `第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组次数` -> `localized_b52953f4`
- Line 1068: `输入次数` -> `s_u5165_reps`
- Line 1099: `第 \(parentSetNumber) 组\(exerciseSet.setType.displayName)子组，\(exerciseSet.isCompleted ? ` -> `localized_afe4bc46`
- Line 1100: `双击切换完成状态` -> `s_u51fb_q_h_done_z_t`

## `VitalStride/Sources/ActivitySummaryCard.swift`

- Line 21: `今日活动` -> `today_h_d`
- Line 33: `训练` -> `training`
- Line 34: `\(summary.workoutCount) 次` -> `value_c`
- Line 38: `时长` -> `s_c`
- Line 43: `消耗` -> `x_h`
- Line 60: `\(minutes) 分钟` -> `value_f_z`
- Line 116: `今日活动进度` -> `today_h_d_u8fdb_u5ea6`

## `VitalStride/Sources/ContentView.swift`

- Line 18: `概览` -> `localized_068a68fd`
- Line 21: `概览` -> `localized_068a68fd`
- Line 23: `训练` -> `training`
- Line 26: `训练` -> `training`
- Line 28: `数据` -> `data_tab_title`
- Line 31: `数据` -> `data_tab_title`
- Line 36: `AI 助手` -> `ai_u52a9_s`
- Line 38: `设置` -> `settings`
- Line 41: `设置` -> `settings`

## `VitalStride/Sources/DataImportExportSection.swift`

- Line 13: `数据导入` -> `data_d_u5165`
- Line 17: `导入 GPX/FIT 文件` -> `d_u5165_gpx_fit_w_u4ef6`
- Line 33: `导入历史 (\(importedFiles.count))` -> `d_u5165_l_u53f2_value`
- Line 51: `数据导出` -> `data_d_u51fa`
- Line 57: `导出范围` -> `d_u51fa_u8303_w`
- Line 63: `导出训练数据 (JSON)` -> `d_u51fa_training_data_json`
- Line 74: `导出失败` -> `d_u51fa_s_b`
- Line 78: `确定` -> `q_d`
- Line 96: `导入失败: \(error.localizedDescription)` -> `d_u5165_s_b_value`
- Line 124: `全部` -> `q_u90e8`
- Line 125: `最近一个月` -> `z_j_u4e00_u4e2a_month`
- Line 126: `最近三个月` -> `z_j_u4e09_u4e2a_month`
- Line 127: `最近一年` -> `z_j_u4e00_n`

## `VitalStride/Sources/DataSections/ActiveEnergySection.swift`

- Line 345: `时间范围` -> `time_u8303_w`
- Line 409: `按日明细` -> `a_r_m_x`

## `VitalStride/Sources/DataSections/BodyWeightSection.swift`

- Line 438: `时间范围` -> `time_u8303_w`
- Line 526: `体重记录` -> `t_u91cd_record`

## `VitalStride/Sources/DataSections/GenericHealthDetailView.swift`

- Line 168: `时间范围` -> `time_u8303_w`
- Line 347: `按日明细` -> `a_r_m_x`

## `VitalStride/Sources/DataSections/HeartRateSection.swift`

- Line 398: `时间范围` -> `time_u8303_w`
- Line 472: `心率记录` -> `heart_rate_record`

## `VitalStride/Sources/DataSections/SleepSection.swift`

- Line 503: `时间范围` -> `time_u8303_w`
- Line 582: `按夜明细` -> `a_u591c_m_x`

## `VitalStride/Sources/DataSections/StepsSection.swift`

- Line 331: `时间范围` -> `time_u8303_w`
- Line 399: `按日明细` -> `a_r_m_x`

## `VitalStride/Sources/DataView.swift`

- Line 125: `需要 HealthKit 授权` -> `x_y_healthkit_s_u6743`
- Line 127: `请前往设置页面授权访问健康数据，授权后即可查看心率、步数等数据。` -> `q_q_u5f80_settings_y_m_s_u6743_u8bbf_w_j_u5eb7_data_s_u6743_u540e_u5373_k_u67e5_`
- Line 235: `活动` -> `h_d`
- Line 277: `心脏` -> `x_u810f`
- Line 327: `身体测量` -> `body_u6d4b_l`
- Line 345: `睡眠` -> `localized_55aab917`
- Line 395: `营养` -> `localized_2e63a2f7`
- Line 408: `运动` -> `workout`

## `VitalStride/Sources/HealthKitPermissionSection.swift`

- Line 13: `心率` -> `heart_rate`
- Line 14: `步数` -> `steps_s`
- Line 15: `睡眠` -> `localized_39962f9e`
- Line 16: `训练记录` -> `training_record`
- Line 17: `活动能量` -> `h_d_n_l`
- Line 18: `体重` -> `t_u91cd`
- Line 19: `基础代谢` -> `localized_a8ad922b`
- Line 20: `步行+跑步距离` -> `steps_x_u8dd1_steps_j_u79bb`
- Line 21: `骑行距离` -> `localized_8a4baf00`
- Line 22: `锻炼时间` -> `localized_8e0dae5f`
- Line 23: `站立时间` -> `localized_ddd1154a`
- Line 24: `已爬楼层` -> `y_u722c_u697c_u5c42`
- Line 25: `体脂率` -> `t_u8102_l`
- Line 26: `去脂体重` -> `q_u8102_t_u91cd`
- Line 27: `身高` -> `s_high`
- Line 29: `静息心率` -> `localized_c59a376c`
- Line 30: `心率变异性` -> `heart_rate_b_u5f02_x`
- Line 31: `最大摄氧量` -> `z_d_u6444_u6c27_l`
- Line 32: `膳食能量` -> `localized_65762626`
- Line 33: `蛋白质` -> `localized_218349c0`
- Line 34: `碳水化合物` -> `localized_6ad7c1ac`
- Line 35: `脂肪` -> `localized_09801676`
- Line 36: `饮水量` -> `localized_2cecad81`
- Line 50: `HealthKit 权限` -> `healthkit_u6743_u9650`
- Line 52: `授权状态` -> `s_u6743_z_t`
- Line 67: `请求授权` -> `q_u6c42_s_u6743`
- Line 80: `管理 HealthKit 权限` -> `localized_c5c3c065`
- Line 90: `请求的数据类型` -> `q_u6c42_d_data_l_x`
- Line 101: `待授权` -> `localized_7cc0340c`
- Line 103: `未知` -> `w_z`
- Line 105: `已请求授权` -> `y_q_u6c42_s_u6743`
- Line 107: `检查中…` -> `j_u67e5_z`
- Line 109: `未知` -> `w_z`

## `VitalStride/Sources/OnboardingView.swift`

- Line 38: `跳过` -> `localized_d6c02dbc`
- Line 61: `你的健康数据 + AI 分析助手` -> `localized_ed2df2b4`
- Line 77: `核心功能` -> `localized_41199721`
- Line 84: `训练记录` -> `training_record`
- Line 85: `记录力量训练，追踪每组重量和次数` -> `record_l_l_training_u8ffd_u8e2a_m_z_weight_h_reps`
- Line 89: `健康数据` -> `j_u5eb7_data`
- Line 90: `心率、步数、睡眠、体重、活动能量一目了然` -> `heart_rate_steps_s_u7761_u7720_t_u91cd_h_d_n_l_u4e00_m_l_r`
- Line 94: `AI 分析` -> `ai_f_u6790`
- Line 95: `智能分析训练数据，提供个性化建议` -> `localized_7144c56f`
- Line 114: `连接健康数据` -> `connection_j_u5eb7_data`
- Line 118: `VitalStride 需要访问你的健康数据来展示心率、步数等信息，并将训练记录写入 HealthKit。` -> `vitalstride_x_y_u8bbf_w_u4f60_d_j_u5eb7_data_l_u5c55_s_heart_rate_steps_s_d_x_x_`
- Line 133: `授权 HealthKit` -> `s_u6743_healthkit`
- Line 141: `稍后再说` -> `localized_cb596a59`
- Line 170: `左滑继续` -> `localized_a44aafc1`

## `VitalStride/Sources/OverviewView.swift`

- Line 55: `概览` -> `localized_5ea8da12`
- Line 85: `刷新失败，请稍后重试` -> `localized_d3e69d7d`
- Line 144: `上次更新于 \(relativeTime)` -> `s_c_update_y_value`
- Line 342: `健康数据` -> `j_u5eb7_data`
- Line 426: `开始你的健康旅程` -> `k_s_u4f60_d_j_u5eb7_u65c5_u7a0b`
- Line 429: `授权 HealthKit 查看健康数据快照，或开始你的第一次训练。` -> `s_u6743_healthkit_u67e5_k_j_u5eb7_data_u5feb_u7167_h_k_s_u4f60_d_u7b2c_u4e00_c_t`
- Line 438: `前往「设置」授权 HealthKit` -> `q_u5f80_settings_s_u6743_healthkit`
- Line 441: `切换到设置页面以授权 HealthKit` -> `q_h_d_settings_y_m_u4ee5_s_u6743_healthkit`
- Line 446: `前往「训练」开始第一次训练` -> `q_u5f80_training_k_s_u7b2c_u4e00_c_training`
- Line 449: `切换到训练页面以开始训练` -> `q_h_d_training_y_m_u4ee5_k_s_training`

## `VitalStride/Sources/PlaceholderViews.swift`

- Line 5: `概览 — Coming Soon` -> `localized_06f2ebfa`
- Line 14: `训练 — Coming Soon` -> `training_coming_soon`
- Line 23: `数据 — Coming Soon` -> `data_coming_soon`
- Line 41: `设置 — Coming Soon` -> `settings_coming_soon`
- Line 48: `概览` -> `localized_06b5611e`
- Line 49: `训练` -> `training`
- Line 50: `数据` -> `data_tab_title`
- Line 52: `设置` -> `settings`

## `VitalStride/Sources/RecentWorkoutsSection.swift`

- Line 9: `最近训练` -> `z_j_training`
- Line 13: `暂无训练记录` -> `z_none_training_record`
- Line 67: `\(exerciseCount) 个动作` -> `value_u4e2a_d_u4f5c`
- Line 89: `力量训练` -> `l_l_training`
- Line 90: `跑步` -> `localized_66602356`
- Line 91: `骑行` -> `localized_f3848fe6`
- Line 92: `游泳` -> `localized_3e78aa5f`
- Line 93: `瑜伽` -> `localized_ec1c4f5a`
- Line 94: `徒步` -> `localized_13d54f5e`
- Line 95: `步行` -> `steps_x`
- Line 96: `划船` -> `localized_6239c381`
- Line 97: `椭圆机` -> `localized_30acecbd`
- Line 98: `核心训练` -> `localized_4d44203a`
- Line 99: `柔韧性` -> `localized_6d038c9b`
- Line 100: `其他` -> `q_u4ed6`

## `VitalStride/Sources/SettingsView.swift`

- Line 14: `设置` -> `settings`
- Line 19: `关于` -> `g_y`
- Line 21: `版本` -> `b_b`
- Line 30: `开源协议与致谢` -> `k_y_u534f_u8bae_u4e0e_u81f4_u8c22`
- Line 46: `VitalStride 使用了以下开源技术和框架：` -> `vitalstride_u4f7f_y_l_u4ee5_x_k_y_u6280_u672f_h_u6846_u67b6`
- Line 52: `用户界面框架` -> `y_u6237_u754c_m_u6846_u67b6`
- Line 53: `数据持久化` -> `data_c_u4e45_h`
- Line 54: `健康数据访问` -> `j_u5eb7_data_u8bbf_w`
- Line 55: `数据可视化` -> `data_k_s_h`
- Line 56: `跨设备同步` -> `localized_216505a6`
- Line 59: `致谢` -> `localized_bb14811d`
- Line 80: `致谢` -> `localized_bb14811d`

## `VitalStride/Sources/StartWorkoutView.swift`

- Line 32: `空白训练` -> `k_u767d_training`
- Line 34: `从零开始，逐个添加动作` -> `c_u96f6_k_s_u9010_u4e2a_add_d_u4f5c`
- Line 46: `从历史复制` -> `c_l_u53f2_f_u5236`
- Line 59: `从模板开始` -> `c_m_b_k_s`
- Line 71: `开始训练` -> `k_s_training`
- Line 75: `取消` -> `cancel`
- Line 110: `\(count) 个动作` -> `value_u4e2a_d_u4f5c`

## `VitalStride/Sources/UnitPreferencesSection.swift`

- Line 9: `公斤 (kg)` -> `localized_f22942e4`
- Line 10: `磅 (lb)` -> `localized_e37d5af5`
- Line 28: `公里 (km)` -> `localized_1ac5caa8`
- Line 29: `英里 (mi)` -> `localized_0d4be3db`
- Line 71: `千卡 (kcal)` -> `localized_7bcd562e`
- Line 72: `千焦 (kJ)` -> `localized_ad9f2352`
- Line 106: `单位偏好` -> `d_u4f4d_u504f_h`
- Line 112: `重量` -> `weight`
- Line 120: `距离` -> `j_u79bb`
- Line 128: `能量` -> `n_l`

## `VitalStride/Sources/WorkoutDetailView.swift`

- Line 25: `概要` -> `localized_8aa38ddc`
- Line 26: `日期` -> `date`
- Line 30: `时长` -> `s_c`
- Line 34: `\(hours) 小时 \(minutes) 分钟` -> `value_x_s_value_f_z`
- Line 34: `\(minutes) 分钟` -> `value_f_z`
- Line 37: `动作数` -> `d_u4f5c_s`
- Line 42: `总组数` -> `z_z_s`
- Line 54: `消耗热量` -> `x_h_r_l`
- Line 97: `动作` -> `d_u4f5c`
- Line 99: `无记录` -> `none_record`
- Line 104: `第 \(index + 1) 组` -> `localized_31e0f7c2`
- Line 110: `\(exerciseSet.reps) 次` -> `value_c`
- Line 113: `热身` -> `r_s`
- Line 166: `训练详情` -> `training_detail`

## `VitalStride/Sources/WorkoutListView.swift`

- Line 281: `\(exerciseCount) 个动作` -> `value_u4e2a_d_u4f5c`

## `VitalStride/Sources/WorkoutTrendChart.swift`

- Line 6: `周` -> `week`
- Line 7: `月` -> `month`
- Line 44: `训练趋势` -> `training_u8d8b_u52bf`
- Line 47: `时间范围` -> `time_u8303_w`
- Line 59: `日期` -> `date`
- Line 60: `时长` -> `s_c`
- Line 68: `均值` -> `localized_9f043688`
- Line 72: `均值 \(Int(averageMinutes))m` -> `localized_2469c793`

## `VitalStrideMac/Sources/MacContentView.swift`

- Line 4: `概览` -> `localized_b7cd9f3e`
- Line 5: `训练` -> `training`
- Line 6: `数据` -> `data_tab_title`
- Line 8: `设置` -> `settings`
- Line 24: `概览` -> `localized_b7cd9f3e`
- Line 25: `训练` -> `training`
- Line 26: `数据` -> `data_tab_title`
- Line 27: `AI 助手` -> `ai_u52a9_s`
- Line 28: `设置` -> `settings`
- Line 59: `请选择一个功能区域` -> `q_select_u4e00_u4e2a_g_n_q_u57df`

## `VitalStrideMac/Sources/PlaceholderViews.swift`

- Line 5: `概览 — Coming Soon` -> `localized_580062eb`
- Line 14: `训练 — Coming Soon` -> `training_coming_soon`
- Line 23: `数据 — Coming Soon` -> `data_coming_soon`
- Line 41: `设置 — Coming Soon` -> `settings_coming_soon`
- Line 48: `概览` -> `localized_b94f063f`
- Line 49: `训练` -> `training`
- Line 50: `数据` -> `data_tab_title`
- Line 52: `设置` -> `settings`

## `VitalStrideWatch Watch App/Sources/WatchContentView.swift`

- Line 8: `力量训练 — Coming Soon` -> `l_l_training_coming_soon`
- Line 11: `开始训练` -> `k_s_training`
- Line 13: `开始训练` -> `k_s_training`
