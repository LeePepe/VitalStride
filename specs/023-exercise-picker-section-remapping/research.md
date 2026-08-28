# Research: `assisted` 与 `weighted` 来源和语义

**Evidence revision**: `332f8e9a0a2e299303ddde9e79b90336499b83f5`

## Conclusion

`assisted=15` 与 `weighted=36` 不是本地名称分析、动作数量阈值或 picker 运行时逻辑生成的分类。两者都是固定上游快照的原始 `sourceData.equipment` 标签，经导入器 1:1 规范化为 catalog 顶层 Equipment，再由本地 `Equipment.section` 静态映射成同名 picker section。

所有 51 条都来自 `hasaneyldrm/exercises-dataset`，都有 `sourceData`，且上游 equipment 与 catalog 顶层 equipment mismatch 为 0。

## Provenance and classification chain

| Step | Source field or local rule | Evidence |
|---|---|---|
| 1 | 固定上游 `hasaneyldrm/exercises-dataset` commit `7455efae41b330c265e7cd4b78dfa848e7ce5ebd` 与 SHA-256 `656634224b8977b99a6d765470ee123260d4979715eaa4e7c0b7c8bb0d79f93d` | `scripts/exercises_dataset_provenance.json` |
| 2 | 上游原始字段 `equipment` 原样保存在 `sourceData.equipment` | `scripts/import_mit_exercises.py` 的 `SOURCE_DATA_KEYS` / `source_data_for_row` |
| 3 | `EQUIPMENT_MAP` 仅做 raw-value 规范化：`assisted→assisted`、`weighted→weighted` | `scripts/import_mit_exercises.py:66-95,166-167` |
| 4 | `build_upstream_row` 把规范化结果写入 catalog 顶层 `equipment`，不读取名称或说明来推断 | `scripts/import_mit_exercises.py:249-296` |
| 5 | Seeder 将顶层 `equipment` 直接解码为 `Equipment`，并写入 `Exercise.equipment`；`sourceData.equipment` 仅作审计字符串 | `VitalStride/Sources/ExerciseSeeder.swift:33-83,233-268` |
| 6 | `Exercise.section` 委托 `equipment.section` | `Packages/VitalModels/Sources/VitalModels/Models/Exercise.swift:29-31` |
| 7 | 当前本地映射才决定 picker section：`.assisted→.assisted`、`.weighted→.weighted` | `Packages/VitalModels/Sources/VitalModels/Enums/Equipment.swift:34-65` |
| 8 | Picker 按 `exercise.section` 分桶，按 `ExerciseSection.allCases` 排序，并通过 `compactMap` 移除空 section | `VitalStride/Sources/ExercisePickerSectionGrouping.swift:4-36` |

History corroboration: upstream Equipment support entered in commit `7ba2872`; the separate picker `ExerciseSection` mapping entered later in commit `f39d100`. Upstream taxonomy and local product grouping are therefore distinct decisions.

## Complete `assisted` list (15)

Every row below has `source=hasaneyldrm/exercises-dataset`, `sourceData.equipment=assisted`, and catalog `equipment=assisted`.

| Source ID | Catalog UUID | English name | Chinese name |
|---|---|---|---|
| `0011` | `44adbf28-29c6-596b-a42c-b53890c53419` | Assisted Hanging Knee Raise | 助力悬垂提膝 |
| `0010` | `a16643c7-d203-55db-b183-06299d9817c7` | Assisted Hanging Knee Raise With Throw Down | 助力悬垂提膝加下压 |
| `1708` | `39a91987-3055-57a5-a58d-daf650bd6de5` | Assisted Lying Calves Stretch | 助力仰卧小腿拉伸 |
| `1709` | `0426969e-b186-563b-a4e9-a57e861e5eb3` | Assisted Lying Glutes Stretch | 助力仰卧臀肌拉伸 |
| `1710` | `59a51d94-8e2d-5a62-9f4f-f20281231b15` | Assisted Lying Gluteus And Piriformis Stretch | 助力仰卧臀肌与梨状肌拉伸 |
| `0012` | `7040a4cf-ac99-567b-83a0-4f99d2e557de` | Assisted Lying Leg Raise With Lateral Throw Down | 助力仰卧举腿加侧向下压 |
| `0013` | `d880db22-34da-568f-92d3-eab949df13b6` | Assisted Lying Leg Raise With Throw Down | 助力仰卧举腿加下压 |
| `0016` | `79e948a9-730a-59f7-9f90-d5060bb72c8a` | Assisted Prone Hamstring | 助力俯卧腘绳肌拉伸 |
| `1713` | `78cdcb68-e262-54eb-bec9-f4edaed5bd69` | Assisted Prone Lying Quads Stretch | 助力俯卧股四头肌拉伸 |
| `1714` | `380cfe67-34ec-5cd7-99a6-b9d59663bb50` | Assisted Prone Rectus Femoris Stretch | 助力俯卧股直肌拉伸 |
| `1716` | `1f5ddcb4-208a-520a-969b-9e1a9ee8f00f` | Assisted Seated Pectoralis Major Stretch With Stability Ball | 助力坐姿胸大肌拉伸（配瑞士球） |
| `1712` | `f71f13f1-ce5f-5dfe-be1c-b3e131ed4c0c` | Assisted Side Lying Adductor Stretch | 助力侧卧内收肌拉伸 |
| `1758` | `7606a7bd-2ff3-54fb-8e43-7140e02283e7` | Assisted Sit-Up | 助力仰卧起坐 |
| `0018` | `c37da052-67a6-5621-8838-00ffdcb6c451` | Assisted Standing Triceps Extension (with Towel) | 助力站姿三头肌伸展（用毛巾） |
| `1259` | `cf7995a3-3105-5421-a77d-8f78f8f6384b` | Behind Head Chest Stretch | 颈后胸部拉伸 |

### Assisted semantic samples

- `0011 Assisted Hanging Knee Raise`: instructions describe an ordinary pull-up-bar knee raise and do not describe assistance.
- `1708 Assisted Lying Calves Stretch`: instructions use the exerciser's hands or a towel for self-assistance.
- `1716 ... With Stability Ball`: instructions explicitly use a stability ball, while the upstream equipment remains `assisted`.
- `0016 Assisted Prone Hamstring`: the only assisted row whose English instructions explicitly mention a partner/assistance option.
- `1259 Behind Head Chest Stretch`: neither name nor instructions describe assistance; it is a self-stretch despite the upstream label.

Eight of 15 assisted names are stretches. Across the whole catalog, 29 names contain “assisted” but their Equipment values span `assisted`, `leverage_machine`, `bodyweight`, `band`, `cable`, and `medicine_ball`; actual assisted-machine movements are mainly `leverage_machine`. The label is therefore a noisy movement modality, not a coherent apparatus.

## Complete `weighted` list (36)

Every row below has `source=hasaneyldrm/exercises-dataset`, `sourceData.equipment=weighted`, and catalog `equipment=weighted`.

| Source ID | Catalog UUID | English name | Chinese name |
|---|---|---|---|
| `0641` | `16b5956b-2cfd-5d41-b7b2-d1c99bd3117c` | Otis Up | 奥蒂斯仰卧起坐 |
| `0830` | `a23acf94-4fc1-5c59-b648-08f74342e98f` | Weighted Bench Dip | 负重长凳臂屈伸 |
| `2987` | `9e698953-16d7-5995-b595-4fce98e417dd` | Weighted Close Grip Chin-Up On Dip Cage | 负重窄距引体向上（臂屈伸架） |
| `3643` | `b594bac9-823e-5fd8-9d94-fa3090b35718` | Weighted Cossack Squats (male) | 负重哥萨克深蹲 |
| `0832` | `c048e8ac-3638-58ec-9c78-cba4b08f68fc` | Weighted Crunch | 负重卷腹 |
| `3670` | `30b4406e-cda9-51be-87b9-f3bd4b8a9a3f` | Weighted Decline Sit-Up | 负重下斜仰卧起坐 |
| `0833` | `2bf018a6-7034-5681-99f0-93e09a06f9ac` | Weighted Donkey Calf Raise | 负重驴式提踵 |
| `1310` | `ac598149-07a1-5fcb-8e3e-d99f880e2ce7` | Weighted Drop Push Up | 负重下落俯卧撑 |
| `2135` | `4c47b017-7cce-5782-b28c-272e3b02d551` | Weighted Front Plank | 负重平板支撑 |
| `0834` | `46f6d864-277f-5dd4-b867-3c6153bf1c58` | Weighted Front Raise | 负重前平举 |
| `0866` | `aebb2896-60b4-5546-8922-9129770c0188` | Weighted Hanging Leg-Hip Raise | 负重悬垂举腿提髋 |
| `0835` | `346d6565-f7e5-5239-b4d2-681bfe558c19` | Weighted Hyperextension (on Stability Ball) | 负重山羊挺身（瑜伽球） |
| `3641` | `211850de-faa4-558d-8271-df0501c00dd8` | Weighted Kneeling Step With Swing | 负重跪姿摆臂上步 |
| `3644` | `ac17c808-d21a-5c08-8fb2-1eb7b1793aa4` | Weighted Lunge With Swing | 负重摆臂箭步蹲 |
| `3286` | `6ecf438c-b710-53ce-8cdc-8c09ca1617e8` | Weighted Muscle Up | 负重双力臂 |
| `3312` | `05aeb615-3900-590d-9928-15ee6d030de3` | Weighted Muscle Up (on Bar) | 负重双力臂（单杠） |
| `3290` | `a1bff4dd-5263-577b-a0bb-207a8ab21494` | Weighted One Hand Pull Up | 负重单手引体向上 |
| `0840` | `cb250e5a-6743-5c70-81a7-6f4615d1a04f` | Weighted Overhead Crunch (on Stability Ball) | 负重过顶卷腹（瑜伽球） |
| `0841` | `759995c6-90b0-5efb-b078-dce9f76e95a9` | Weighted Pull-Up | 负重引体向上 |
| `0844` | `603497a2-40c3-54f2-8415-e6e71cc46f8f` | Weighted Round Arm | 负重绕臂 |
| `0846` | `0407e3ca-c3bf-578f-af07-d354f70f3a31` | Weighted Russian Twist | 负重俄罗斯转体 |
| `0845` | `5c5f486b-d014-5210-bc86-677c7d3eff7e` | Weighted Russian Twist (legs Up) | 负重俄罗斯转体（抬腿） |
| `2371` | `b7cf36fe-17c6-5e8a-9e73-0ce309d8e973` | Weighted Russian Twist V. 2 | 负重俄罗斯转体 V2 |
| `0849` | `82879aae-3d2a-5a3d-8387-9ba0358c36ea` | Weighted Seated Twist (on Stability Ball) | 负重坐姿转体（瑜伽球） |
| `0850` | `279e9d16-043a-5c1f-9b22-0143caa109a3` | Weighted Side Bend (on Stability Ball) | 负重体侧屈（瑜伽球） |
| `0851` | `2e6e73fc-cfbf-55fe-b95e-79f39cdb7a07` | Weighted Sissy Squat | 负重西西里深蹲 |
| `0852` | `f1b2e5c0-a086-5231-9dcd-828ded8ec72d` | Weighted Squat | 负重深蹲 |
| `0853` | `2ce062d3-9e6e-5be2-b978-13617a60c45e` | Weighted Standing Curl | 负重站姿弯举 |
| `0854` | `ee602f6e-8c2c-5c9d-bebd-0232805ae87c` | Weighted Standing Hand Squeeze | 负重站姿握力挤压 |
| `3313` | `a9041bd9-fa30-506f-a96a-5e3d7af25f5a` | Weighted Straight Bar Dip | 负重直杠臂屈伸 |
| `3642` | `3466d297-a707-56c8-925f-c40add0d6f16` | Weighted Stretch Lunge | 负重伸展箭步蹲 |
| `0856` | `64545f64-2b6a-5f8f-834d-bcbe76d22e95` | Weighted Svend Press | 负重斯文德夹胸推 |
| `1754` | `fa5c54a3-4fcb-5372-b78e-fbe9582a4a25` | Weighted Three Bench Dips | 负重三凳臂屈伸 |
| `1755` | `22a84114-dff0-5c62-8a8d-6b8e79263bfd` | Weighted Tricep Dips | 负重肱三头肌臂屈伸 |
| `1767` | `a3a8534d-cec4-575a-b5a6-5687198432e9` | Weighted Triceps Dip On High Parallel Bars | 负重高双杠肱三头肌臂屈伸 |
| `0859` | `50dd43ce-c978-5192-ba0e-f66056ca7d51` | Wrist Rollerer | 腕力棒卷绕 |

### Weighted semantic samples

- `0834 Weighted Front Raise`: instructions explicitly use two dumbbells despite the upstream generic `weighted` label.
- `0832 Weighted Crunch`: instructions allow a plate or dumbbell.
- `0846 Weighted Russian Twist`: instructions allow a generic weight or medicine ball.
- `0841 Weighted Pull-Up`: the name says weighted, but instructions describe a pull-up without naming the added load.
- `0859 Wrist Rollerer`: instructions attach a weight to a rope or bar; the name itself omits “weighted”.
- `0641 Otis Up`: neither the name nor preserved instructions identify a load, yet the upstream label is `weighted`.

Weighted spans arms, back, chest, core, legs, and shoulders. Thirty-four of 36 names include “Weighted”; the two exceptions above remain upstream-tagged weighted. Conversely, a “Weighted Seated Bicep Curl on Stability Ball” row is upstream-tagged `medicine_ball`, demonstrating again that names do not drive classification.

## Decision analysis

### Delivery topology for the unmerged layer stack

The AppUI test patch must compile against the reviewed T001 mapping while keeping VitalModels outside T002's change surface. Three delivery shapes were evaluated:

- **Branch from `main`, target `main`**: rejected because `main` lacks the reviewed mapping, so T002's expected distribution cannot become green independently.
- **Branch from PR #418 head, target `main`**: rejected because the T002 pull request would include the inherited unmerged VitalModels range and violate T002's AppUI-only scope.
- **Publish a reviewed planning descendant of PR #418 head, branch T002 from it, and target the PR #418 source branch**: selected. Let `H0=cb78fe8c70071c11f91bf400b00ef14b7812e771`, `P` be the fresh planning-only reviewed descendant, and `H1` be the T002 implementation head. `P...H1` contains only T002's two test files, while `H0...H1` contains only independently reviewed planning artifacts plus those tests. PR #418 can later fast-forward to `H1` without losing either reviewed range.

Squash, rebase, cherry-pick, or a merge commit would create a head different from `H1`. The selected contract therefore requires fast-forward-only integration after MY-1491 merges to `main`, followed by a fresh required PR #418 run. Any intervening branch movement or rewrite of `P`/`H1` invalidates the review and requires a new descendant chain plus fresh review.

### `assisted`: merge to Bodyweight

**Recommendation confidence: medium-high.** Assisted describes a way the movement is performed, not a consistent device. Most rows are stretches or calisthenic/core movements; actual machine-assisted exercises are already represented by Leverage Machine. Bodyweight is the least misleading existing target and keeps all 15 actions discoverable.

- Retain rejected: “Assisted / 辅助器械” overstates a coherent apparatus that the records do not have.
- Other rejected as primary choice: taxonomically safe but less discoverable than Bodyweight for this mostly self-/partner-assisted movement set.
- Hide rejected: all 15 are valid catalog actions.

### `weighted`: retain Weighted

**Recommendation confidence: high.** Weighted is not one apparatus, but it is a coherent user-facing training mode and a substantial 36-row bucket. The records intentionally span bodyweight-plus-load, dumbbells, medicine balls, rope/bar loads, and unspecified external resistance; no single specific equipment section is accurate.

- Merge to Bodyweight rejected: curls, front raises, squats and wrist rolling are not uniformly bodyweight.
- Merge to Dumbbell/Barbell rejected: preserved instructions use multiple or unspecified implements.
- Merge to Other rejected: it would bury a meaningful 36-row loaded-movement group larger than several retained sections.
- Hide rejected: all 36 are valid catalog actions.

## Reproducible evidence queries

From repository root:

```bash
jq -r '.exercises[] | select(.equipment == "assisted" or .equipment == "weighted") | [.equipment,.id,.nameEn,.source,.sourceData.id,.sourceData.equipment,.sourceData.category,.sourceData.body_part,.sourceData.target] | @tsv' VitalStride/Resources/exercises.json

jq '[.exercises[] | select(.equipment == "assisted" or .equipment == "weighted")] | group_by(.equipment) | map({equipment:.[0].equipment,count:length,sources:(group_by(.source)|map({source:.[0].source,count:length})),mismatch:(map(select(.equipment != .sourceData.equipment))|length),missingSourceData:(map(select(.sourceData == null))|length)})' VitalStride/Resources/exercises.json
```
