# 图标源文件 / Icon sources

这里是 **复盘志** App 图标（Icon Composer 文档）的**唯一源**。`PortfolioAgent/AppIcon.icon`
是生成的产物，不要手改；改这里的 `palette.json` 或 `layers/*.svg`，然后重新生成。

```
docs/brand/icon/
  palette.json        颜色（按外观）、分组与图层元数据
  layers/*.svg        白色 alpha 蒙版，一个文件一层
```

## 生成与验证（在 `ios/` 目录）

```sh
swift scripts/build-app-icon.swift            # 生成 PortfolioAgent/AppIcon.icon
swift scripts/build-app-icon.swift --verify  # 校验 + 用 ictool 渲染六个 iOS 外观
swift scripts/build-app-icon.swift --previews # 另出预览图到 docs/brand/assets/icon-renders/
```

渲染由 Apple 自带的 `ictool`（Icon Composer.app 内）完成，与系统同一套渲染；
也可以直接在 Icon Composer 里打开 `PortfolioAgent/AppIcon.icon` 查看图层与各外观。
DSH 沙箱里若 `swift` 无法写 clang module cache，加 `-module-cache-path /tmp/swift-module-cache`。

## 结构

五层、四组，前 → 后（数组第一个在最上层，这是 Icon Composer 的约定）：

| 组 | 资产 | 作用 | 默认色 |
| --- | --- | --- | --- |
| Conclusion | `accent.svg` | 结论横线：复盘后留下的那一句 | `#3D6BFF` |
| Ink | `ink.svg` | 趋势线 + 箭头 + 两条分析横线 | `#14181D` |
| Hardware | `hw.svg` | 两支交叉画架腿（板顶没有夹子） | `#14181D` |
| Board | `surface.svg` | 白板书写面 | `#FBFAF4` |
| Board | `frame.svg` | 白板边框（自动渐变填充） | `#C9D3EE` |

画布 1024×1024。**构图比例：图案（白板 + 画架腿的整体外接框）占方框的
1/φ ≈ 61.8%**，外接框 632.9×629.9，四周留白约 195.6 / 197.0，整体居中。
下列几何是缩放后的坐标（缩放系数 0.732485，由原始几何按外接框与画布中心对齐而来）：

| 元素 | 数值 |
| --- | --- |
| 白板外框 | x 195.57, y 197.03, 632.87×465.86, r21.97 |
| 边框厚度 | 19.04（书写面 x214.61, y216.08, 594.78×427.77, r2.93） |
| 画架腿 | (438.75,671.68)→(756.65,809.39) 与 (599.9,671.68)→(267.35,809.39)，线宽 35.16，圆头 |
| 趋势线 | (246.84,572.06) (334.74,475.38) (393.34,525.18) (637.99,343.53)，线宽 23.44，圆头 |
| 箭头 | 从 (637.99,343.53) 向后两撇，长 55.67、张角 ±30°、线宽 23.44 |
| 结论横线（蓝） | x602.83, y468.05, 171.4×20.51, r10.25 |
| 分析横线（墨） | x602.83, y522.99, 120.13×20.51；x602.83, y577.92, 76.18×20.51 |

原始（未缩放）几何保留在下表，便于按比例改写；两者只差一个系数，形状不变：

| 元素 | 原始数值（1024 画布，缩放前） |
| --- | --- |
| 白板外框 | x 80, y 100, 864×636, r30 |
| 边框厚度 | 26（书写面 x106, y126, 812×584, r4） |
| 画架腿 | (412,748)→(846,936) 与 (632,748)→(178,936)，线宽 48，圆头 |
| 趋势线 | (150,612) (270,480) (350,548) (684,300)，线宽 32，圆头 |
| 箭头 | 从 (684,300) 向后两撇，长 76、张角 ±30°、线宽 32 |
| 结论横线（蓝） | x636, y470, 234×28, r14 |
| 分析横线（墨） | x636, y545, 164×28；x636, y620, 104×28 |

缩放/居中变换（改比例时按这个重算）：
`p' = (512, 512) + (p − (512, 530)) × 0.732485`。

> 图标顶部没有夹子：白板上沿就是图案的最高点。`hw.svg` 只含两支画架腿。

## 六个外观

| 外观 | 来源 |
| --- | --- |
| Default | `fills.light` |
| Dark | `fills.dark` |
| TintedLight / TintedDark | `fills.tinted` |
| ClearLight / ClearDark | 系统由 alpha 与默认色自动派生，不单独配色 |

`palette.json` → `icon.json` 的编码规则（由 `build-app-icon.swift` 负责，已用 ictool 反证）：

- 一个图层要么只有 `fill`（固定色），要么只有 `fill-specializations`（含一个无 `appearance`
  的默认项）。**两者同时出现时 `fill-specializations` 会被静默忽略**，所以生成器只写后者。
- 组与组内图层的数组顺序都是**前 → 后**。
- 最多 4 个可见组。
- SVG 里不能有 `<text>`；CoreSVG 会静默丢弃。
- 形状不要小于画布 ~3%（29pt 下会糊）；高光/折射/厚度由系统负责，不要烘进图形。
