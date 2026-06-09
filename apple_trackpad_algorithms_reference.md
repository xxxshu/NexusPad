# Apple MacBook 触控板算法技术参考手册

## 目录

1. [多点触控跟踪算法](#1-多点触控跟踪算法)
2. [手势识别算法](#2-手势识别算法)
3. [手掌误触过滤](#3-手掌误触过滤)
4. [速度与加速度曲线](#4-速度与加速度曲线)
5. [Force Touch 与触觉反馈](#5-force-touch-与触觉反馈)
6. [坐标处理与滤波](#6-坐标处理与滤波)
7. [专利与逆向工程](#7-专利与逆向工程)
8. [相关开源项目与参考](#8-相关开源项目与参考)

---

## 1. 多点触控跟踪算法

### 1.1 硬件层：电容感应矩阵

Apple 触控板使用**电容感应矩阵**检测手指接触。矩阵由纵横排列的电极网格组成，当手指靠近时改变局部电容值。传感器扫描整个网格，产生一个二维电容值矩阵（类似热力图），然后通过以下步骤提取触点：

1. **阈值检测**：电容值超过噪声门限的区域标记为触点候选
2. **连通域分析**：将相邻的超阈值像素聚合为触点"斑块"（blob）
3. **亚像素插值**：使用质心算法（centroid）计算每个触点的精确坐标，精度可达 ~0.1mm
4. **椭圆拟合**：对每个触点拟合椭圆，提取主轴/次轴（majorAxis/minorAxis）、方向角等几何特征

### 1.2 传输协议：BCM5974 帧格式

Linux 内核的 `bcm5974.c` 驱动（[源码](https://elixir.bootlin.com/linux/latest/source/drivers/input/mouse/bcm5974.c)）逆向了 Apple 触控板的 USB 数据协议。每个触控板报告由**帧头 + N 个手指数据块**组成：

#### 帧类型与尺寸

| 类型 | 帧头大小 (字节) | 按钮偏移 | 每指数据大小 (字节) | 适用设备 |
|------|----------------|---------|-------------------|---------|
| TYPE1 | 26 | 独立端点 | 28 | 早期 MacBook |
| TYPE2 | 30 | 15 | 28 | Wellspring 初代 |
| TYPE3 | 38 | 23 | 28 | Wellspring 3-8 (无需模式切换) |
| TYPE4 | 46 | 31 | 30 | Wellspring 9+ (Force Touch) |

#### 手指数据结构 (`tp_finger`)

```c
struct tp_finger {
    __le16 origin;       // 触点切换标志 (0=新手指)
    __le16 abs_x;        // 绝对 X 坐标
    __le16 abs_y;        // 绝对 Y 坐标
    __le16 rel_x;        // 相对 X 偏移
    __le16 rel_y;        // 相对 Y 偏移
    __le16 tool_major;   // 工具区域主轴 (触点感知区域)
    __le16 tool_minor;   // 工具区域次轴
    __le16 orientation;  // 方向 (16384=点, 其他=15位弧度角)
    __le16 touch_major;  // 触点区域主轴
    __le16 touch_minor;  // 触点区域次轴
    __le16 unused[2];    // 保留
    __le16 pressure;     // 压力值 (Force Touch)
    __le16 multi;        // 多指标志
} __attribute__((packed, aligned(2)));
```

每个手指数据块为 14-15 个 16-bit 小端整数（28-30 字节）。帧中最多报告 **16 个手指** (`MAX_FINGERS = 16`)。

#### 解析逻辑

```
手指数量 = (数据总长度 - 帧头大小) / 每指数据大小
```

- `touch_major == 0` 的手指被过滤（无效触点）
- Y 坐标需要翻转：`y = y_min + y_max - raw_y`
- 触点尺寸左移 1 位：`ABS_MT_TOUCH_MAJOR = raw2int(touch_major) << 1`
- 方向值反转：`orientation = 16384 - raw_orientation`

### 1.3 手指跟踪与身份分配

#### 帧间手指跟踪

Apple 使用 **最近邻匹配**（Nearest Neighbor）策略在连续帧之间关联手指：

- 每个手指具有**唯一标识符**（identity / identifier），在手指存续期间保持不变
- 新出现的手指获得新 ID
- 手指消失（lift-off）后 ID 被释放
- `origin` 字段在触点切换跟踪时被清零

#### 手指重新着陆（Re-landing）

当手指短暂抬起后重新落下时，系统通过以下启发式判断是否为同一手指：

1. **空间距离**：新触点与上一个消失触点的位置距离
2. **时间阈值**：从抬起到重新着陆的时间间隔
3. **轨迹连续性**：运动方向是否与抬手前的轨迹一致
4. **接触形状相似度**：椭圆形状（长宽比、方向角）是否匹配

#### MTTouch 状态机（macOS 私有框架）

通过逆向 `MultitouchSupport.framework` 获得的触点状态：

| 状态位 | 值 | 含义 |
|-------|---|------|
| `touching` | 0x1 | 正在接触 |
| `starting` | 0x2 | 刚开始接触 (began) |
| `ending` | 0x4 | 接触结束 (ended) |

### 1.4 各代设备坐标范围

| 设备代号 | X 范围 | Y 范围 | 最大压力 | 最大宽度 |
|---------|--------|--------|---------|---------|
| Wellspring (Air 1.1) | -4824 ~ 5342 | -172 ~ 5820 | 256 | 2048 |
| Wellspring3 (MB 5,1) | -4460 ~ 5166 | -75 ~ 6700 | 300 | 2048 |
| Wellspring5 (MBP 8) | -4415 ~ 5050 | -55 ~ 6680 | 300 | 2048 |
| Wellspring7 (MBP 10.x) | -4750 ~ 5280 | -150 ~ 6730 | 300 | 2048 |
| Wellspring9 (MBP 12,1) | -4828 ~ 5345 | -203 ~ 6803 | 300 | 2048 |

#### 信号噪声比（SNR）与模糊过滤

| 参数 | SN 比 | 计算方式 |
|------|-------|---------|
| 压力 | 45 | fuzz = (max - min) / 45 |
| 宽度 | 25 | fuzz = (max - min) / 25 |
| 坐标 | 250 | fuzz = (max - min) / 250 |
| 方向 | 10 | fuzz = (max - min) / 10 |

`fuzz` 值用于内核输入子系统的**抖动过滤**——小于 fuzz 的变化被视为噪声。

---

## 2. 手势识别算法

### 2.1 事件管线架构

```
硬件传感器 → 固件 → USB/HID 报告 → IOHIDFamily (内核) → MultitouchSupport.framework
→ CoreGesture/WindowServer → NSEvent → NSGestureRecognizer / 应用层
```

### 2.2 手势类型与检测

#### 滚动（Scroll，双指滑动）

**识别条件**：
- 两个触点向大致相同方向移动
- 触点间向量的**对齐度**（点积）> 阈值
- 速度超过最小门限

**API 数据**：
- `NSEvent.scrollingDeltaX/Y`：精确浮点增量（trackpad 上 `hasPreciseScrollingDeltas = true`）
- `NSEvent.phase`：手势阶段（began → changed → ended）
- `NSEvent.momentumPhase`：惯性滚动阶段

#### 缩放（Pinch/Magnification）

**识别条件**：
- 两个触点之间的**距离**发生变化
- 距离增大的为放大（zoom in），距离缩小的为缩小（zoom out）

**计算公式**：
```
magnification = log(d_current / d_initial)
```
其中 `d` 为两指间欧氏距离。使用对数确保缩放比例与实际大小成比例。

**API**：`NSEvent.magnification`（CGFloat，正值=放大，负值=缩小）

#### 旋转（Rotation）

**识别条件**：
- 两指间连线的**角度**发生变化
- 使用 `atan2(Δy, Δx)` 计算向量角度

**计算**：
```
rotation = atan2(p2_current - p1_current) - atan2(p2_initial - p1_initial)
```

**API**：`NSEvent.rotation`（CGFloat，单位为**度**，正值=顺时针）

#### 滑动（Swipe，三/四指滑动）

**识别条件**：
- 三或四个触点向同一方向快速移动
- 速度超过较高阈值（比滚动快）
- 方向一致性极高
- 作为离散事件而非连续事件报告

**API**：`NSEvent.deltaX/deltaY`（±1.0，标识方向）

#### Force Click（深按）

**识别条件**：
- 压力超过第一阈值（普通点击，Stage 1）
- 继续施压超过第二阈值（Force Click，Stage 2）

**API**：`NSEvent.pressure`（0.0 ~ 1.0），`NSEvent.stage`（0/1/2）

### 2.3 手势消歧（Disambiguation）

滚动、缩放和旋转都可以用两指操作完成，Apple 使用启发式规则消歧：

1. **初始运动分析**：手势开始的前 100-200ms 内分析运动模式
   - 两指**同向平行移动** → 滚动
   - 两指**反向分离/靠近** → 缩放
   - 两指**旋转运动** → 旋转
   - 混合运动通过主导分量判定

2. **速度向量分解**：将两指运动分解为以下分量：
   - **平移分量**（centroid 移动方向和距离）
   - **缩放分量**（两指距离变化率）
   - **旋转分量**（两指连线角度变化率）

3. **滞后（Hysteresis）**：一旦识别为某种手势，在运动回归到阈值以下之前不会切换到其他手势，防止频繁误切

4. **互斥锁定**：在一次连续触控中，系统通常只识别一种手势类型（滚动或缩放或旋转），不同时报告多种

### 2.4 NSGestureRecognizer 状态机

```
possible → began → [changed] → ended (recognized)
                ↘ failed
                ↘ cancelled
```

| 状态 | 含义 |
|------|------|
| `possible` | 识别器正在观察，尚未确定 |
| `began` | 手势已识别 |
| `changed` | 手势持续中，参数更新 |
| `ended` | 手势完成 |
| `failed` | 不是此手势 |
| `cancelled` | 被系统取消 |

---

## 3. 手掌误触过滤

### 3.1 分层架构

Apple 的手掌过滤分为**硬件层**和**软件层**：

#### 硬件/固件层
- 触控板固件首先对接收到的触点进行初步分类
- 通过 IOHIDFamily 内核驱动传递分类结果

#### 内核层 (IOHIDFamily)

触点分类枚举（`IOHIDEventContactType`）：

| 值 | 名称 | 含义 |
|----|------|------|
| 0 | `kIOHIDEventContactTypeUndefined` | 未分类 |
| 1 | `kIOHIDEventContactTypeFinger` | 手指（有效输入） |
| 2 | `kIOHIDEventContactTypePalm` | 手掌（需要过滤） |
| 3 | `kIOHIDEventContactTypeThumb` | 拇指 |
| 4 | `kIOHIDEventContactTypeStylus` | 触控笔 |

#### 用户空间层 (MultitouchSupport.framework)

`MTTouch` 结构的 `isResting` 字段标记为"休息触点"（即手掌/手腕），应用层可据此过滤。

### 3.2 判定启发式规则

手掌过滤使用以下多维特征进行判定：

#### 面积检测

| 特征 | 手指 | 手掌 |
|------|------|------|
| 接触面积 | ~30-60 mm² | ~100+ mm² |
| 椭圆形状 | 近圆形 (长宽比 ≈ 1) | 扁长形 (长宽比 >> 1) |
| 边缘特征 | 锐利、清晰 | 弥散、模糊 |

**关键阈值**：接触面积超过约 100 mm² 的触点被视为手掌候选。

#### 运动分析

| 特征 | 手指 | 手掌 |
|------|------|------|
| 速度 | 快速、有目的 | 静止或缓慢漂移 |
| 加速度 | 有明确的加速/减速模式 | 无规律 |
| 方向 | 有明确轨迹 | 随机或不动 |

#### 位置分析

- 触控板**边缘区域**使用更严格的手掌过滤阈值
- 与活跃手指**空间接近**的大型触点更可能是手掌
- 手腕通常出现在触控板下边缘

#### 时间分析

- 手掌通常**先于手指**到达触控板（手放下时手腕先接触）
- 手掌的**停留时间**远长于手指
- 快速出现又快速消失的小触点不太可能是手掌

### 3.3 macOS NSTouch 的 isResting 属性

```swift
let touches = event.touches(matching: .touching, in: self)
for touch in touches {
    if touch.isResting {
        // 这是手掌/手腕触点，忽略
        continue
    }
    // 处理有效的手指输入
}
```

### 3.4 MultitouchSupport.framework 中的触摸质量

`kIOHIDEventFieldDigitizerQuality` 或类似的"触摸质量"指标被用于辅助判定：
- 高质量 = 明确的手指接触
- 低质量 = 模糊的或大面积接触（可能是手掌）

---

## 4. 速度与加速度曲线

### 4.1 惯性滚动（Momentum Scrolling）

Apple 的惯性滚动使用**指数衰减模型**：

#### 核心公式

```
v(t) = v₀ × r^t
```

其中：
- `v₀` = 手指离开瞬间的初始速度
- `r` = 衰减率（deceleration rate）
- `t` = 时间步数（帧数）

#### UIScrollView 的衰减率常数（iOS，macOS 行为类似）

| 常量 | 值 | 效果 |
|------|-----|------|
| `UIScrollView.DecelerationRate.normal` | 0.998 | 较长的滑行距离，"漂浮"感 |
| `UIScrollView.DecelerationRate.fast` | 0.990 | 较快停止，"干脆"感 |

#### 滚动偏移量计算

```
offset(n) = offset_initial + v₀ × (1 - r^n) / (1 - r)
```

#### 停止条件

当剩余速度低于阈值（约 **0.1 点/帧**）时，惯性滚动终止。

#### 完全停止时间估算

```
T ≈ -ln(v_threshold / v₀) / (-ln(r))
```

以 normal 衰减率为例：`-ln(0.998) ≈ 0.002`，若 `v₀ = 1000 pt/s`，则 `T ≈ ln(10000) / 0.002 ≈ 4605 帧 ≈ 77 秒`（理论值，实际会更早因速度不足而停止）。

### 4.2 速度追踪算法

#### macOS NSEvent 速度计算

macOS 不直接暴露"瞬时速度"属性。应用需要自行计算：

```swift
class ScrollVelocityTracker {
    private var samples: [(time: TimeInterval, delta: CGPoint)] = []
    private let maxSamples = 5  // 保留最近5个样本

    func update(event: NSEvent) {
        let sample = (time: event.timestamp,
                      delta: CGPoint(x: event.scrollingDeltaX,
                                     y: event.scrollingDeltaY))
        samples.append(sample)
        if samples.count > maxSamples {
            samples.removeFirst()
        }
    }

    var velocity: CGPoint {
        guard samples.count >= 2 else { return .zero }
        let first = samples.first!
        let last = samples.last!
        let dt = last.time - first.time
        guard dt > 0 else { return .zero }
        // 时间加权的累积位移除以时间间隔
        let totalDelta = samples.reduce(CGPoint.zero) {
            CGPoint(x: $0.x + $1.delta.x, y: $0.y + $1.delta.y)
        }
        return CGPoint(x: totalDelta.x / dt, y: totalDelta.y / dt)
    }
}
```

#### 速度平滑

Apple 使用**多采样加权平均**来计算平滑速度：
- 通常使用最近 3-5 个事件的加权平均
- 较新的样本权重更高
- 速度在手指抬起瞬间被"冻结"并用于惯性滚动

### 4.3 光标加速曲线

macOS 的光标加速是非线性的，将物理移动速度映射到屏幕光标速度：

#### 加速模型（类 libinput 多项式模型）

```
acceleration_factor = 1.0 + coefficient × speed^exponent
```

#### 特征点

- **低速区域**（< ~5 mm/s）：1:1 或极低加速，精确操作
- **中速区域**（~5-50 mm/s）：线性到二次加速
- **高速区域**（> ~50 mm/s）：加速因子有上限封顶

#### "跟踪速度"偏好

macOS 系统偏好中的"跟踪速度"滑条调整的是加速曲线的参数：
- 低速 = 更低的系数和指数，曲线更平坦
- 高速 = 更高的系数和指数，曲线更陡峭

### 4.4 橡皮筋回弹效果（Rubber Banding）

当滚动到达内容边界时，Apple 使用**对数/渐近曲线**：

```
offset = c × ln(1 + x / c)
```

其中 `c` 为弹性系数（通常约为内容视图尺寸的 1/3 ~ 1/2）。此公式确保：
- 越拉越难拉（力与距离成对数关系而非线性）
- 松手后平滑回弹
- 不会出现"弹过头"的情况

---

## 5. Force Touch 与触觉反馈

### 5.1 硬件架构

2015 年后的 MacBook 触控板采用全新的无物理移动设计：

```
┌─────────────────────────────────────┐
│           触控板表面（玻璃）           │
├─────────────────────────────────────┤
│  [应变传感器1]          [应变传感器2]  │
│                                      │
│           电容触控传感器矩阵           │
│                                      │
│  [应变传感器3]          [应变传感器4]  │
├─────────────────────────────────────┤
│           Taptic Engine              │
│        (线性谐振致动器 LRA)           │
└─────────────────────────────────────┘
```

#### 四个应变传感器（Strain Gauge）

- 位于触控板四角/背面
- 检测表面形变（施加压力时的微小弯曲）
- 输出与施加力成正比的电压信号
- 四路信号可计算压力的**位置和大小**

#### Taptic Engine（线性谐振致动器）

- 电磁驱动的线性马达
- 可产生精确控制的振动（模拟"点击"感）
- 响应时间极短（约 10ms 内达到峰值）
- 支持不同强度和质感的触觉反馈

### 5.2 两阶段压力检测

```
压力轴:  ──────┬──────────┬──────────►
              Stage 1    Stage 2
            (普通点击)  (Force Click)
              ~0.5N       ~1.5N
```

#### Stage 1：普通点击

- 压力超过第一阈值（约 0.5N，因设备而异）
- Taptic Engine 产生第一次"咔嗒"反馈
- 等同于传统触控板的物理点击

#### Stage 2：Force Click

- 压力继续增大超过第二阈值（约 1.5N）
- Taptic Engine 产生更强的第二次"咔嗒"
- 触发 Force Touch 特有功能（查词、预览链接、重命名文件等）

#### 连续压力值

`NSEvent.pressure` 提供 0.0 ~ 1.0 的连续压力值：
- 0.0 ~ 0.5：未点击，正在按压
- 0.5 附近：Stage 1 触发点
- 0.5 ~ 1.0：持续按压
- 1.0 附近：Stage 2 触发点

### 5.3 压力位置计算

四路应变传感器的读数用于计算压力中心：

```
force_x = (F_topright + F_bottomright - F_topleft - F_bottomleft) / total_force
force_y = (F_topleft + F_topright - F_bottomleft - F_bottomright) / total_force
```

这确保无论你按触控板的哪个位置，Force Touch 都能正确工作。

### 5.4 触觉反馈算法

Taptic Engine 的驱动波形经过精心设计：

1. **点击波形**：短脉冲（~5-10ms），快速上升、快速衰减
2. **强度控制**：通过改变脉冲幅度模拟不同的"按压深度感"
3. **位置补偿**：根据压力位置调整触觉反馈强度，使触感在触控板各处一致
4. **时间同步**：触觉反馈与 Stage 切换严格同步（延迟 < 10ms）

### 5.5 相关专利

| 专利号 | 标题 | 关键内容 |
|--------|------|---------|
| US 9,178,509 | Force sensing touch surface | 应变传感器架构 |
| US 9,632,598 | Force sensing through a tactile surface | 力感测实现 |
| US 8,981,909 | Adjustment of a haptic response | 触觉响应调节 |
| US 9,535,500 | Variable impedance for force detection | 可变阻抗力检测 |

---

## 6. 坐标处理与滤波

### 6.1 坐标处理管线

```
原始电容值 → 阈值检测 → 连通域分析 → 质心计算(亚像素)
  → 椭圆拟合 → 坐标归一化 → 噪声过滤 → 加速曲线映射 → 屏幕坐标
```

### 6.2 原始坐标归一化

#### bcm5974 驱动的坐标转换

```c
// 1. 读取原始16位有符号坐标
int raw_x = le16_to_cpu(finger->abs_x);
int raw_y = le16_to_cpu(finger->abs_y);

// 2. 坐标变换 (Y轴翻转)
int x = raw_x;
int y = y_min + y_max - raw_y;

// 3. 使用 bcm5974_params 进行归一化
// origin: 零点偏移
// sens: 灵敏度 (单位/mm)
```

#### macOS MultitouchSupport.framework 归一化

触控板坐标被归一化到 0.0 ~ 1.0 范围：
```swift
let normalizedX = touch.normalizedPosition.x  // 0.0 ~ 1.0
let normalizedY = touch.normalizedPosition.y  // 0.0 ~ 1.0
```

归一化公式：
```
normalized_x = (raw_x - x_min) / (x_max - x_min)
normalized_y = (raw_y - y_min) / (y_max - y_min)
```

### 6.3 噪声过滤

#### 模糊因子（Fuzz）过滤

内核输入子系统使用 `fuzz` 值过滤抖动：

```c
// 只有变化量 > fuzz 时才报告新的坐标值
if (abs(new_value - old_value) > fuzz) {
    report_event(new_value);
}
```

Apple 触控板的 fuzz 值由 SNR 计算得出：

| 轴 | SNR | 典型 fuzz 值 |
|----|-----|-------------|
| X 坐标 | 250 | (5345+4828)/250 ≈ 40 |
| Y 坐标 | 250 | (6803+203)/250 ≈ 28 |
| 压力 | 45 | 300/45 ≈ 6 |
| 宽度 | 25 | 2048/25 ≈ 82 |

#### 指数移动平均（EMA）

macOS 在触控板坐标处理中使用 EMA 平滑：

```
y(t) = α × x(t) + (1-α) × y(t-1)
```

- `α` 较大（~0.7-0.9）：低延迟，少平滑（快速移动时）
- `α` 较小（~0.3-0.5）：高延迟，多平滑（慢速移动时）

**速度自适应平滑**：移动速度越快，平滑越少（减少延迟）；移动速度越慢，平滑越多（减少抖动）。

### 6.4 边缘处理

- 触控板**边缘区域**（约 2-5mm）可能有更严格的噪声过滤
- 边缘区域的触点可能被限制或截断
- 防止手掌误触在边缘区域尤其重要

### 6.5 坐标到屏幕的映射

macOS 使用**非线性加速曲线**（不是简单的 DPI 比例）：

```
screen_delta = physical_delta × acceleration(speed)
```

其中 `acceleration(speed)` 是一个分段函数：
- 低速：因子接近 1.0（1:1 映射）
- 中速：因子线性增长
- 高速：因子有上限（约 5-10x）

---

## 7. 专利与逆向工程

### 7.1 关键 Apple 专利

| 专利号 | 标题 | 核心内容 |
|--------|------|---------|
| **US 7,479,949** | Touch screen device...determining commands by applying heuristics | 触摸手势启发式判定算法，多点触控命令识别 |
| **US 7,844,914** | Detecting and interpreting real-world and security gestures | 手势检测与解释，安全手势识别 |
| **US 8,059,101** | Multipoint touchscreen | 多点触控感应控制器架构 |
| **US 7,461,352** | Movable touch pad with added functionality | 惯性滚动、动量滚动算法 |
| **US 9,178,509** | Force sensing touch surface | 力感测触控表面，应变传感器设计 |
| **US 9,632,598** | Force sensing through a tactile surface | 触觉表面力感测实现 |
| **US 8,981,909** | Adjustment of a haptic response | 触觉响应调节算法 |

#### 专利中的核心算法思路

**US 7,479,949（手势启发式）**：
- 定义了多点触控设备上的手势分类规则
- 使用手指数量、移动方向、速度、加速度等特征
- 通过启发式规则树将原始触点序列映射为命令
- 涵盖滚动、缩放、旋转、滑动等手势的判定逻辑

**US 8,059,101（多点触控）**：
- 描述电容感应矩阵的扫描和读取架构
- 多点触控控制器如何同时追踪多个触点
- 解决"鬼点"（ghost point）问题的电路设计

### 7.2 FingerWorks 技术遗产

Wayne Westerman 和 John Elias 在 University of Delaware 创立了 **FingerWorks** 公司，开发了多点触控手势识别技术。Apple 于 2005 年收购了 FingerWorks，其技术成为 MacBook 触控板和 iPhone 多点触控的基础。

FingerWorks 的原始专利涵盖了：
- 多指手势识别算法
- 手掌/手腕过滤技术
- 触点形状分析用于区分手指和手掌
- 手势状态机设计

### 7.3 逆向工程成果

#### Linux bcm5974 驱动

- **作者**：Henrik Rydberg（主要），Jonathan Nieder（协议逆向）
- **位置**：`drivers/input/mouse/bcm5974.c`（Linux 内核）
- **成果**：完整逆向了 Apple 触控板的 USB HID 数据协议
- **贡献**：解密了帧格式、手指数据结构、坐标范围、压力/宽度编码

#### MacBook 12" SPI 驱动

- **项目**：[macbook12-spi-driver](https://github.com/cb22/macbook12-spi-driver)（[备用链接](https://github.com/roadrunner2/macbook12-spi-driver)）
- **成果**：逆向了 2015 年后 MacBook 的 SPI 触控板协议
- **发现**：SPI 触控板使用与 USB 版本**相同的触控数据格式**

#### MultitouchSupport.framework 逆向

社区通过逆向工程重建了 macOS 私有框架的 API：

```c
// 设备管理
CFArrayRef MTDeviceCreateList(void);
MTDeviceRef MTDeviceCreateDefault(void);
void MTDeviceStart(MTDeviceRef device, int callback_type);
void MTDeviceStop(MTDeviceRef device);

// 回调注册
void MTRegisterContactFrameCallback(MTDeviceRef device,
    void (*callback)(MTDeviceRef, MTTouch*, int touches, double timestamp, int frame));

// MTTouch 结构 (逆向重建)
struct MTTouch {
    int frame;              // 帧号
    double timestamp;       // 时间戳
    int identifier;         // 触点唯一 ID
    int state;              // 状态位 (touching=1, starting=2, ending=4)
    int fingerID;           // 手指 ID
    int handID;             // 手 ID (左手/右手)
    MTPoint normalizedPosition;  // 归一化位置 (0.0~1.0)
    MTVector velocity;      // 速度向量
    float angle;            // 触点角度
    float majorAxis;        // 椭圆主轴
    float minorAxis;        // 椭圆次轴
    float pressure;         // 压力值
    float size;             // 触点大小
};
```

---

## 8. 相关开源项目与参考

### 8.1 驱动与底层库

| 项目 | 链接 | 说明 |
|------|------|------|
| Linux bcm5974 | [内核源码](https://elixir.bootlin.com/linux/latest/source/drivers/input/mouse/bcm5974.c) | Apple 触控板 USB 驱动，协议逆向参考 |
| macbook12-spi-driver | [GitHub](https://github.com/cb22/macbook12-spi-driver) | MacBook 12" SPI 触控板驱动 |
| libinput | [GitLab](https://gitlab.freedesktop.org/libinput/libinput) | Linux 输入设备库，包含加速曲线实现 |
| mtdev | [GitHub](https://github.com/freedesktop-org-dev/mtdev) | 多点触控协议转换库 |
| IOHIDFamily | [Apple OSS](https://github.com/apple-oss-distributions/IOHIDFamily) | Apple 开源的 HID 家族，含触控处理逻辑 |

### 8.2 手势与应用层

| 项目 | 说明 |
|------|------|
| BetterTouchTool | macOS 触控板手势定制工具，使用 MultitouchSupport.framework 私有 API |
| touchegg | Linux 触控板手势识别守护进程 |
| libinput-gestures | 基于 libinput 的 Linux 手势识别工具 |
| Karabiner-Elements | macOS 键盘/输入设备定制，涉及 HID 事件拦截 |

### 8.3 加速曲线参考

#### libinput 加速算法

libinput 的触控板加速使用**多项式曲线**：

```
accel_factor = 1.0 + speed_out × pow(speed_in, exponent)
```

其中：
- `speed_in`：指针速度（单位/mm）
- `speed_out`：加速系数
- `exponent`：指数（通常 2.0 左右）
- 速度由**多采样加权滤波器**计算

**Peter Hutterer**（libinput 主要开发者）的博客文章详细解释了此算法：
- 博客：[who-t.blogspot.com](https://who-t.blogspot.com/2018/03/libinput-touchpad-pointer-acceleration.html)
- 核心观点：好的加速曲线应该让中速操作获得小加速、高速操作获得大加速，同时保持低速精确性

### 8.4 技术分析参考

| 资源 | 说明 |
|------|------|
| Apple Developer - NSEvent | [文档](https://developer.apple.com/documentation/appkit/nsevent) | macOS 事件系统 API |
| Apple Developer - NSTouch | [文档](https://developer.apple.com/documentation/appkit/nstouch) | 单触点抽象 |
| Apple Developer - UIGestureRecognizer | [文档](https://developer.apple.com/documentation/uikit/uigesturerecognizer) | 手势识别器基类 |
| Google Patents | [patents.google.com](https://patents.google.com) | Apple 专利全文搜索 |
| iFixit Magic Trackpad 2 拆解 | [iFixit](https://www.ifixit.com/Teardown/Magic+Trackpad+2+Teardown/50892) | 硬件架构分析 |

---

## 附录 A：关键数值速查表

| 参数 | 值 | 来源 |
|------|-----|------|
| 最大同时追踪手指数 | 16 | bcm5974 驱动 |
| 手指数据块大小 | 28-30 字节 | bcm5974 协议 |
| 坐标精度 | ~0.1mm | 硬件规格 |
| 坐标 SNR | 250 | bcm5974 参数 |
| 压力 SNR | 45 | bcm5974 参数 |
| UIScrollView.normal 衰减率 | 0.998 | iOS/macOS API |
| UIScrollView.fast 衰减率 | 0.990 | iOS/macOS API |
| 惯性滚动停止阈值 | ~0.1 pt/frame | 逆向分析 |
| 橡皮筋弹性公式 | offset = c × ln(1 + x/c) | 逆向分析 |
| Force Touch Stage 1 压力 | ~0.5N | 拆解分析 |
| Force Touch Stage 2 压力 | ~1.5N | 拆解分析 |
| Taptic Engine 响应时间 | ~10ms | 硬件规格 |
| 手掌接触面积阈值 | ~100 mm² | 启发式估算 |
| 手指接触面积 | ~30-60 mm² | 典型值 |
| 触控板帧率 | ~100-200 Hz | 硬件规格 |

## 附录 B：相关专利检索指南

在 [Google Patents](https://patents.google.com) 上使用以下检索式：

```
assignee:"Apple Inc." AND ("multitouch" OR "touchpad" OR "trackpad") AND ("gesture" OR "tracking" OR "palm rejection")
```

```
assignee:"Apple Inc." AND "force touch" AND ("haptic" OR "strain" OR "pressure sensor")
```

```
inventor:"Westerman" AND assignee:"Apple Inc."
```

---

*本文档基于 Linux 内核 bcm5974 驱动源码、Apple 公开 API 文档、MultitouchSupport.framework 逆向工程、Apple 公开专利、libinput 源码分析、以及 iOS/macOS 滚动行为逆向研究综合编写。部分内部实现细节为基于可观测行为的推断，Apple 未公开完整算法实现。*

*编写日期：2026-06-09*
