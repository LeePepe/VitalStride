# Contract: Equipment → Picker Section

## Current 17-section decision table

| Current section | Current count | Decision | Final target | Display name (en / zh-Hans) |
|---|---:|---|---|---|
| `assisted` | 15 | Merge | `bodyweight` | Bodyweight / 自重 |
| `band` | 54 | Retain | `band` | Band / 弹力带 |
| `barbell` | 204 | Retain | `barbell` | Barbell / 杠铃 |
| `bodyweight` | 361 | Retain | `bodyweight` | Bodyweight / 自重 |
| `cable` | 196 | Retain | `cable` | Cable / 绳索 |
| `dumbbell` | 345 | Retain | `dumbbell` | Dumbbell / 哑铃 |
| `ez_barbell` | 23 | Retain | `ez_barbell` | EZ Barbell / EZ 曲杆 |
| `kettlebell` | 61 | Retain | `kettlebell` | Kettlebell / 壶铃 |
| `leverage_machine` | 81 | Retain | `leverage_machine` | Leverage Machine / 杠杆器械 |
| `machine` | 38 | Retain | `machine` | Machine / 固定器械 |
| `medicine_ball` | 13 | Merge | `other` | Other / 其他 |
| `other` | 30 | Retain and absorb | `other` | Other / 其他 |
| `rope` | 10 | Merge | `other` | Other / 其他 |
| `sled_machine` | 15 | Merge | `other` | Other / 其他 |
| `smith_machine` | 48 | Retain | `smith_machine` | Smith Machine / 史密斯机 |
| `stability_ball` | 28 | Merge | `other` | Other / 其他 |
| `weighted` | 36 | Retain | `weighted` | Weighted / 负重 |

No section is hidden; all 1,558 catalog rows remain discoverable.

## Complete 29-Equipment mapping

| Equipment | Final section | Equipment | Final section |
|---|---|---|---|
| `assisted` | `bodyweight` | `band` | `band` |
| `barbell` | `barbell` | `dumbbell` | `dumbbell` |
| `machine` | `machine` | `bodyweight` | `bodyweight` |
| `bosu_ball` | `other` | `cable` | `cable` |
| `elliptical_machine` | `other` | `ez_barbell` | `ez_barbell` |
| `hammer` | `other` | `kettlebell` | `kettlebell` |
| `leverage_machine` | `leverage_machine` | `medicine_ball` | `other` |
| `olympic_barbell` | `other` | `resistance_band` | `other` |
| `roller` | `other` | `rope` | `other` |
| `skierg_machine` | `other` | `sled_machine` | `other` |
| `smith_machine` | `smith_machine` | `stability_ball` | `other` |
| `stationary_bike` | `other` | `stepmill_machine` | `other` |
| `tire` | `other` | `trap_bar` | `other` |
| `upper_body_ergometer` | `other` | `weighted` | `weighted` |
| `wheel_roller` | `other` | — | — |

Other receives exactly 17 Equipment values: `bosu_ball`, `elliptical_machine`, `hammer`, `medicine_ball`, `olympic_barbell`, `resistance_band`, `roller`, `rope`, `skierg_machine`, `sled_machine`, `stability_ball`, `stationary_bike`, `stepmill_machine`, `tire`, `trap_bar`, `upper_body_ergometer`, `wheel_roller`.

## Final visible order and catalog counts

| Order | Section | Display name (en / zh-Hans) | Count |
|---:|---|---|---:|
| 1 | `band` | Band / 弹力带 | 54 |
| 2 | `barbell` | Barbell / 杠铃 | 204 |
| 3 | `bodyweight` | Bodyweight / 自重 | 376 |
| 4 | `cable` | Cable / 绳索 | 196 |
| 5 | `dumbbell` | Dumbbell / 哑铃 | 345 |
| 6 | `ez_barbell` | EZ Barbell / EZ 曲杆 | 23 |
| 7 | `kettlebell` | Kettlebell / 壶铃 | 61 |
| 8 | `leverage_machine` | Leverage Machine / 杠杆器械 | 81 |
| 9 | `machine` | Machine / 固定器械 | 38 |
| 10 | `smith_machine` | Smith Machine / 史密斯机 | 48 |
| 11 | `weighted` | Weighted / 负重 | 36 |
| 12 | `other` | Other / 其他 | 96 |

Total: 1,558.

## Behavior invariants

- Mapping is explicit and exhaustive; no runtime count threshold.
- Search and muscle filtering remove items only.
- A section with zero filtered items is absent from header, index, drag preview, and scroll targets.
- A nonempty section retains its canonical identity and order.
- Custom exercises use the same Equipment mapping.
