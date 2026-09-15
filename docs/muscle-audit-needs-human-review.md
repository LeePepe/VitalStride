# 肌群核对 — 待人工复核清单

## 2026-09-16 归档说明

以下是旧 v4 动作库审计的原始记录，不代表对 v5 数据的重新核验或已批准的修改。
旧提交 `4a732b8` 的提踵修复迁移到 v5 时，仅保留 Machine / Barbell / Seated /
Leg Press Calf Raise 四项：移除辅助肌群中的 `tibialis anterior`。
Donkey Calf Raise 在 v5 中已改为 `hamstrings` / `glutes`，本次保持不变。

范围仅为 bundled catalog 数据修正和历史审计存档，不包含已有安装的 SwiftData 数据回填。
当前 seeder 在 catalog version 和 ID 集合不变时跳过；四个本地动作也不属于 upstream
更新路径。因此本次数据修正适用于新插入的预设，已有预设的定向迁移需要单独跟进，
不能把此提交当作已有用户数据已修复的证据。catalog 保持 v5，避免绕过其专用校验。

## 原始待复核记录

> Dev team (ruflo→raven) 对 7 个规则可疑项的核对结果。**未写入数据**——因判断存在分歧/歧义，需人工裁定。

## 判断分歧信号（为何不自动采用）

- 两个近乎相同的 Neck Stretch 得到**相反结论**（一个 KEEP、一个 FIX）→ LLM 判断不稳定
- 3 个 Shoulder Raise 建议把 primary 从 serratus anterior 改成 deltoids → 改动大，且可能误解动作本意（若原意是肩胛面前锯肌训练）

## 逐项

| 动作 | 分类 | FS判定 | 原 primary | 建议 primary | 备注 |
|---|---|---|---|---|---|
| Barbell Incline Shoulder Raise | chest | FIX | ["serratus anterior"] | ["deltoids"] | ⚠️改primary,需确认动作本意 |
| Dumbbell Incline Shoulder Raise | chest | FIX | ["serratus anterior"] | ["deltoids"] | ⚠️改primary,需确认动作本意 |
| Incline Scapula Push Up | chest | FIX | ["serratus anterior"] | ["serratus anterior"] | ✅去triceps,较可信 |
| Neck Side Stretch | shoulders | KEEP | ["levator scapulae"] | — | ⚠️同类动作结论不一致 |
| Scapula Push-Up | chest | FIX | ["serratus anterior"] | ["serratus anterior"] | ✅去triceps,较可信 |
| Side Push Neck Stretch | shoulders | FIX | ["levator scapulae"] | ["sternocleidomastoid"] | ⚠️同类动作结论不一致 |
| Smith Incline Shoulder Raises | chest | FIX | ["serratus anterior"] | ["deltoids"] | ⚠️改primary,需确认动作本意 |

## 建议

- **可采纳**: Scapula Push-Up / Incline Scapula Push Up 去掉 triceps(肘不动,triceps不参与)
- **需专家定夺**: 3× Shoulder Raise 改 primary; 2× Neck Stretch
