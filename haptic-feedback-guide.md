# 手机触控板项目 —— 触觉反馈（Haptic Feedback）实现指南

> 本文档面向正在开发「手机无线触控板+键盘」Web 控制端的开发者。
> 目标：在手机网页中模拟 MacBook Force Touch 触控板那种「实体按键按下→弹起」的震动反馈体验。

---

## 一、核心背景：为什么这件事很难？

### 1.1 Apple 的触觉反馈系统

MacBook 的 Force Touch 触控板和 iPhone 的 Taptic Engine 由 **Core Haptics** 框架驱动。它有两个关键参数：

| 参数       | 含义                       | 范围 0.0~1.0 |
| ---------- | -------------------------- | ------------ |
| Intensity  | 震动强度（振幅）           | 越大越强     |
| Sharpness  | 震动锐度（波形硬度/频率）  | 越大越"脆"   |

Apple 原生定义了两种基础事件：
- **Transient（瞬态）**：短促、清脆的"嗒"—— 用于点击、键盘按键
- **Continuous（连续）**：持续的震动流 —— 用于拖拽、滚动的持续反馈

我们在网页中无法直接调用 Core Haptics，只能通过浏览器提供的 API 尽可能逼近。

### 1.2 Web 平台的触觉 API 现状

| 平台         | API                          | 支持情况                                    |
| ------------ | ---------------------------- | ------------------------------------------- |
| Android 网页 | `navigator.vibrate()`        | ✅ Chrome/Firefox/Edge/Samsung 全部支持      |
| iOS 网页     | `navigator.vibrate()`        | ❌ **Safari 完全不支持，Apple 拒绝实现**     |
| iOS 网页     | AudioContext 静音触发技巧    | ⚠️ 非官方 hack，可触发微弱 Taptic 反馈      |
| Native App   | Capacitor / 原生插件         | ✅ 完整 Core Haptics / Android Haptic API   |

**结论：纯 Web 方案在 Android 上可以做到不错的效果，在 iOS 上效果有限。**

---

## 二、平台检测与 API 封装

在项目中首先需要一个统一的触觉反馈模块，自动适配不同平台：

```javascript
// haptic.js —— 统一触觉反馈模块

const HapticEngine = (() => {
  let audioCtx = null;
  let isIOSUnlocked = false;
  let isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent);

  // ==================== 初始化 ====================

  /**
   * 初始化触觉引擎（必须在用户首次交互时调用）
   * iOS 需要通过用户手势解锁 AudioContext
   */
  function init() {
    if (isIOS && !isIOSUnlocked) {
      unlockIOSAudio();
    }
  }

  /**
   * iOS 音频解锁 —— 通过播放极短静音来"激活"Taptic Engine
   * 原理：iOS 在用户手势触发的音频播放时，会同步激活 Taptic Engine
   */
  function unlockIOSAudio() {
    try {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      // 播放一段极短的静音 buffer 来解锁音频系统
      const buffer = audioCtx.createBuffer(1, 1, 22050);
      const source = audioCtx.createBufferSource();
      source.buffer = buffer;
      source.connect(audioCtx.destination);
      source.start(0);
      isIOSUnlocked = true;
      console.log('[Haptic] iOS audio system unlocked');
    } catch (e) {
      console.warn('[Haptic] iOS audio unlock failed:', e);
    }
  }

  // ==================== 底层振动方法 ====================

  /**
   * Android 原生振动
   * @param {number|number[]} pattern - 振动时长(ms) 或 振动/暂停交替模式数组
   */
  function vibrateNative(pattern) {
    if ('vibrate' in navigator) {
      navigator.vibrate(pattern);
    }
  }

  /**
   * iOS AudioContext 触觉 hack
   * 通过播放一个极短的低频音频脉冲来触发 Taptic Engine
   * @param {number} durationMs - 脉冲持续时间（影响 Taptic 的响应时长）
   * @param {number} frequency  - 频率 Hz（越低越接近 Taptic 感，推荐 1~5Hz 范围的超低频）
   */
  function iosHapticPulse(durationMs = 10, frequency = 1) {
    if (!audioCtx || audioCtx.state === 'suspended') {
      try {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        audioCtx.resume();
      } catch (e) {
        return; // 无法创建 AudioContext，放弃
      }
    }

    try {
      const durationSec = durationMs / 1000;
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();

      osc.type = 'sine';
      osc.frequency.setValueAtTime(frequency, audioCtx.currentTime);

      // 音量设为极低 —— 我们不要声音，只要振动
      gain.gain.setValueAtTime(0.001, audioCtx.currentTime);
      // 快速淡出避免任何可听噪音
      gain.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + durationSec);

      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.start(audioCtx.currentTime);
      osc.stop(audioCtx.currentTime + durationSec);
    } catch (e) {
      // 静默失败
    }
  }

  // ==================== 公开 API ====================

  return {
    init,

    /**
     * 单击反馈 —— 模拟 Force Touch 轻点
     * Apple 原生参考：Transient, intensity 0.5, sharpness 0.5
     */
    tap() {
      vibrateNative(10);          // Android: 10ms 短促振动
      if (isIOS) iosHapticPulse(8, 1);  // iOS: 超短低频脉冲
    },

    /**
     * 双击反馈 —— 比单击略强、略长
     * Apple 原生参考：两次快速 Transient, intensity 0.6
     */
    doubleTap() {
      vibrateNative([8, 40, 8]);       // Android: 两次短振动间隔 40ms
      if (isIOS) {
        iosHapticPulse(8, 1);
        setTimeout(() => iosHapticPulse(8, 1), 50);
      }
    },

    /**
     * 长按/拖拽起始反馈 —— 模拟手指"抓住"物体的感觉
     * Apple 原生参考：Transient, intensity 0.7, sharpness 0.3（更沉闷）
     */
    dragStart() {
      vibrateNative(20);               // Android: 20ms 中等振动
      if (isIOS) iosHapticPulse(15, 1);
    },

    /**
     * 拖拽结束/释放反馈
     * Apple 原生参考：Transient, intensity 0.4, sharpness 0.7
     */
    dragEnd() {
      vibrateNative(12);
      if (isIOS) iosHapticPulse(8, 1);
    },

    /**
     * 滚轮段落反馈 —— 每滚过一个"刻度"触发一次
     * Apple 原生参考：连续滚动时的段落式 tick
     * @param {number} intensity - 滚动强度系数 0.0~1.0，越快越大
     */
    scrollTick(intensity = 0.5) {
      // 根据强度动态调整振动时长
      const duration = Math.round(6 + intensity * 10); // 6~16ms
      vibrateNative(duration);
      if (isIOS) iosHapticPulse(duration, 1);
    },

    /**
     * 键盘按键反馈
     * Apple 原生参考：Transient, intensity 0.4, sharpness 0.8（非常脆）
     */
    keyPress() {
      vibrateNative(8);               // Android: 8ms 极短脆振
      if (isIOS) iosHapticPulse(6, 1);
    },

    /**
     * 长按拖拽持续反馈 —— 在拖拽过程中持续轻柔振动
     * @param {number} durationMs - 振动持续时长
     */
    dragContinuous(durationMs = 30) {
      if ('vibrate' in navigator) {
        // 创建一个持续的微弱脉冲模式：[振动, 暂停, 振动, 暂停, ...]
        const pulseOn = 8;
        const pulseOff = 12;
        const pattern = [];
        let remaining = durationMs;
        while (remaining > pulseOn) {
          pattern.push(pulseOn);
          remaining -= pulseOn;
          if (remaining > 0) {
            pattern.push(Math.min(pulseOff, remaining));
            remaining -= pulseOff;
          }
        }
        if (pattern.length > 0) vibrateNative(pattern);
      }
      if (isIOS) iosHapticPulse(durationMs, 1);
    },

    /**
     * 立即停止所有振动
     */
    stop() {
      if ('vibrate' in navigator) {
        navigator.vibrate(0);
      }
    }
  };
})();

export default HapticEngine;
```

---

## 三、各场景的具体实现

### 3.1 单指单击反馈（Tap）

**目标**：手指轻点触控板时，给出一下"嗒"的物理按钮感反馈。

**关键点**：
- 需要区分"轻触"和"点击"——只有确认为点击时才触发
- 反馈必须在 `touchstart` 或点击确认的瞬间触发，不能有延迟
- 振动时长要短（10ms），感觉要脆

```javascript
import HapticEngine from './haptic.js';

// 页面加载时初始化（在用户首次交互的事件中调用 init）
document.addEventListener('touchstart', () => HapticEngine.init(), { once: true });

const trackpad = document.getElementById('trackpad');

// ============ 方案 A：简单方案 ============
// 在 touchend 且没有明显移动时触发
let touchStartPos = null;
let touchStartTime = 0;

trackpad.addEventListener('touchstart', (e) => {
  const touch = e.touches[0];
  touchStartPos = { x: touch.clientX, y: touch.clientY };
  touchStartTime = Date.now();
});

trackpad.addEventListener('touchend', (e) => {
  if (!touchStartPos) return;

  const touch = e.changedTouches[0];
  const dx = touch.clientX - touchStartPos.x;
  const dy = touch.clientY - touchStartPos.y;
  const dist = Math.sqrt(dx * dx + dy * dy);
  const duration = Date.now() - touchStartTime;

  // 判定为"点击"的条件：
  // 1. 移动距离 < 10px（几乎没动）
  // 2. 持续时间 < 300ms（快速触碰）
  // 3. 只有一根手指
  if (dist < 10 && duration < 300 && e.touches.length === 0) {
    HapticEngine.tap();  // ✅ 触发单击反馈
  }

  touchStartPos = null;
});


// ============ 方案 B：精确方案（推荐） ============
// 使用 pointer events + 更精细的状态机
class TapDetector {
  constructor(element, onTap) {
    this.element = element;
    this.onTap = onTap;
    this.startX = 0;
    this.startY = 0;
    this.startTime = 0;
    this.moved = false;

    this.element.addEventListener('pointerdown', this.onPointerDown.bind(this));
    this.element.addEventListener('pointermove', this.onPointerMove.bind(this));
    this.element.addEventListener('pointerup', this.onPointerUp.bind(this));
  }

  onPointerDown(e) {
    this.startX = e.clientX;
    this.startY = e.clientY;
    this.startTime = Date.now();
    this.moved = false;
  }

  onPointerMove(e) {
    const dx = e.clientX - this.startX;
    const dy = e.clientY - this.startY;
    if (Math.sqrt(dx * dx + dy * dy) > 8) {
      this.moved = true;
    }
  }

  onPointerUp(e) {
    const duration = Date.now() - this.startTime;
    if (!this.moved && duration < 300 && duration > 30) {
      this.onTap(e);  // 确认为点击
    }
  }
}

new TapDetector(trackpad, () => {
  HapticEngine.tap();
});
```

---

### 3.2 双指双击反馈（Double Tap）

**目标**：快速连续两次单击时，给出更强一点的两段反馈，区别于单击。

**关键点**：
- 两次点击间隔通常 < 300ms 判定为双击
- 第二次点击时反馈——用"双段振动"模式 `[8, 40, 8]` 区分于单击的单段振动

```javascript
class DoubleTapDetector {
  constructor(element, onSingleTap, onDoubleTap) {
    this.element = element;
    this.onSingleTap = onSingleTap;
    this.onDoubleTap = onDoubleTap;
    this.lastTapTime = 0;
    this.singleTapTimer = null;

    this.element.addEventListener('pointerup', this.handleTap.bind(this));
  }

  handleTap(e) {
    const now = Date.now();
    const timeSinceLastTap = now - this.lastTapTime;

    if (timeSinceLastTap < 300 && timeSinceLastTap > 50) {
      // ✅ 双击！
      clearTimeout(this.singleTapTimer);
      this.onDoubleTap();
      this.lastTapTime = 0; // 重置
    } else {
      // 可能是单击，延迟判定（等待看有没有第二次点击）
      this.lastTapTime = now;
      clearTimeout(this.singleTapTimer);
      this.singleTapTimer = setTimeout(() => {
        this.onSingleTap(); // 超时，确认为单击
      }, 300);
    }
  }
}

new DoubleTapDetector(
  trackpad,
  () => HapticEngine.tap(),       // 单击反馈
  () => HapticEngine.doubleTap()  // 双击反馈
);
```

---

### 3.3 长按拖拽反馈（Long Press → Drag）

**目标**：单指放在触控板上保持 0.4s 不动 → 触发"抓住"震动 → 进入拖拽模式 → 拖拽过程中有持续的微弱反馈 → 释放时"松开"震动。

**关键点**：
- 长按确认时给一个明确的"抓取"反馈（比点击更沉）
- 拖拽过程中持续反馈要**非常轻微**，不能喧宾夺主
- 释放时给"放下"反馈

```javascript
class LongPressDragDetector {
  constructor(element, callbacks) {
    this.element = element;
    this.callbacks = callbacks; // { onDragStart, onDragMove, onDragEnd }

    this.LONG_PRESS_DURATION = 400; // 0.4s
    this.MOVE_THRESHOLD = 10;       // 移动超过 10px 视为拖拽

    this.state = 'idle'; // idle → pressing → dragging
    this.longPressTimer = null;
    this.startX = 0;
    this.startY = 0;
    this.currentX = 0;
    this.currentY = 0;
    this.hasMovedBeforeLongPress = false;

    // 持续反馈的定时器
    this.continuousFeedbackTimer = null;

    this.element.addEventListener('pointerdown', this.onDown.bind(this));
    this.element.addEventListener('pointermove', this.onMove.bind(this));
    this.element.addEventListener('pointerup', this.onUp.bind(this));
    this.element.addEventListener('pointercancel', this.onUp.bind(this));
  }

  onDown(e) {
    if (this.state !== 'idle') return;

    this.startX = this.currentX = e.clientX;
    this.startY = this.currentY = e.clientY;
    this.hasMovedBeforeLongPress = false;
    this.state = 'pressing';

    // 启动长按计时器
    this.longPressTimer = setTimeout(() => {
      if (this.state === 'pressing' && !this.hasMovedBeforeLongPress) {
        // ✅ 长按确认！进入拖拽模式
        this.state = 'dragging';

        // ---- 抓取反馈 ----
        HapticEngine.dragStart();

        // ---- 启动持续反馈 ----
        this.startContinuousFeedback();

        this.callbacks.onDragStart?.({
          x: this.startX,
          y: this.startY
        });
      }
    }, this.LONG_PRESS_DURATION);
  }

  onMove(e) {
    this.currentX = e.clientX;
    this.currentY = e.clientY;

    if (this.state === 'pressing') {
      // 还在等待长按确认，检查是否已移动
      const dx = this.currentX - this.startX;
      const dy = this.currentY - this.startY;
      if (Math.sqrt(dx * dx + dy * dy) > this.MOVE_THRESHOLD) {
        // 移动了，取消长按
        this.hasMovedBeforeLongPress = true;
        clearTimeout(this.longPressTimer);
        this.state = 'idle';
      }
    } else if (this.state === 'dragging') {
      // 拖拽中，通知移动
      this.callbacks.onDragMove?.({
        x: this.currentX,
        y: this.currentY,
        dx: this.currentX - this.startX,
        dy: this.currentY - this.startY
      });
    }
  }

  onUp(e) {
    clearTimeout(this.longPressTimer);

    if (this.state === 'dragging') {
      // ✅ 拖拽结束
      this.stopContinuousFeedback();
      HapticEngine.dragEnd();
      this.callbacks.onDragEnd?.({
        x: this.currentX,
        y: this.currentY
      });
    }

    this.state = 'idle';
  }

  /**
   * 拖拽过程中的持续微弱反馈
   * 每隔一小段时间给一次轻微振动，模拟手指在平面上拖动的摩擦感
   */
  startContinuousFeedback() {
    this.continuousFeedbackTimer = setInterval(() => {
      HapticEngine.dragContinuous(20); // 每次 20ms 的微弱脉冲
    }, 100); // 每 100ms 一次
  }

  stopContinuousFeedback() {
    if (this.continuousFeedbackTimer) {
      clearInterval(this.continuousFeedbackTimer);
      this.continuousFeedbackTimer = null;
    }
    HapticEngine.stop();
  }
}

// 使用
new LongPressDragDetector(trackpad, {
  onDragStart(pos) {
    console.log('拖拽开始:', pos);
    // 设置拖拽选区、开始选择文本等
  },
  onDragMove(info) {
    console.log('拖拽中:', info);
    // 更新选区、移动元素等
  },
  onDragEnd(pos) {
    console.log('拖拽结束:', pos);
    // 完成选区、放置元素等
  }
});
```

---

### 3.4 双指滚轮段落反馈（Scroll Detent）

**目标**：双指上下滑动触发滚轮，滚动过程中根据速度产生一段一段的"咔哒咔哒"段落感反馈，类似老式鼠标的滚轮。

**关键点**：
- 需要计算滚动速度（像素/ms）
- 速度越快，反馈间隔越短（但有最小间隔限制避免过于密集）
- 每次"经过一个段落"才触发一次反馈，不是连续触发
- 反馈强度也可以随速度变化

```javascript
class ScrollHapticController {
  constructor(element) {
    this.element = element;

    // ---- 段落反馈参数 ----
    this.TICK_DISTANCE = 50;       // 每滚过 50px 触发一次段落反馈（可调节）
    this.MIN_TICK_INTERVAL = 40;   // 两次反馈最小间隔 40ms（避免太快）
    this.MAX_TICK_INTERVAL = 200;  // 两次反馈最大间隔 200ms

    // ---- 状态 ----
    this.accumulatedDistance = 0;   // 累计滚动距离
    this.lastTickTime = 0;         // 上次反馈时间
    this.lastTickY = 0;            // 上次触发反馈时的 Y 坐标
    this.isScrolling = false;
    this.scrollVelocity = 0;       // 滚动速度 (px/ms)
    this.lastMoveTime = 0;
    this.lastMoveY = 0;
    this.velocitySamples = [];     // 速度采样

    // ---- 绑定触摸事件 ----
    this.element.addEventListener('touchstart', this.onTouchStart.bind(this), { passive: false });
    this.element.addEventListener('touchmove', this.onTouchMove.bind(this), { passive: false });
    this.element.addEventListener('touchend', this.onTouchEnd.bind(this));
  }

  onTouchStart(e) {
    if (e.touches.length === 2) {
      this.isScrolling = true;
      this.accumulatedDistance = 0;
      this.lastTickY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
      this.lastMoveY = this.lastTickY;
      this.lastMoveTime = Date.now();
      this.lastTickTime = 0;
      this.velocitySamples = [];
    }
  }

  onTouchMove(e) {
    if (!this.isScrolling || e.touches.length !== 2) return;
    e.preventDefault(); // 阻止页面默认滚动（如果你自己处理滚动的话）

    const now = Date.now();
    const currentY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
    const deltaY = currentY - this.lastMoveY;
    const deltaTime = now - this.lastMoveTime;

    // 计算瞬时速度
    if (deltaTime > 0) {
      const velocity = Math.abs(deltaY) / deltaTime;
      // 保留最近 5 个速度采样取平均（平滑）
      this.velocitySamples.push(velocity);
      if (this.velocitySamples.length > 5) {
        this.velocitySamples.shift();
      }
      this.scrollVelocity = this.velocitySamples.reduce((a, b) => a + b, 0) / this.velocitySamples.length;
    }

    // 累计滚动距离（取 Y 方向变化量的绝对值）
    const distanceFromLastTick = Math.abs(currentY - this.lastTickY);
    this.accumulatedDistance += Math.abs(deltaY);

    // ---- 判断是否应该触发段落反馈 ----
    const timeSinceLastTick = now - this.lastTickTime;

    // 根据速度动态调整触发距离：滚得快 → 每段距离更短 → 反馈更频繁
    const dynamicTickDistance = this.getDynamicTickDistance();

    if (
      this.accumulatedDistance >= dynamicTickDistance &&
      timeSinceLastTick >= this.MIN_TICK_INTERVAL
    ) {
      // ✅ 触发段落反馈！
      const intensity = this.getIntensity();
      HapticEngine.scrollTick(intensity);

      // 重置累计
      this.accumulatedDistance = 0;
      this.lastTickTime = now;
      this.lastTickY = currentY;
    }

    this.lastMoveY = currentY;
    this.lastMoveTime = now;
  }

  onTouchEnd(e) {
    if (e.touches.length < 2) {
      this.isScrolling = false;
      this.scrollVelocity = 0;
      this.velocitySamples = [];
    }
  }

  /**
   * 根据滚动速度动态调整段落距离
   * 速度越快，段落距离越短 → 反馈越频繁（模拟快速滚动滚轮的连续咔哒感）
   */
  getDynamicTickDistance() {
    // scrollVelocity 单位是 px/ms
    // 慢速 (0~0.5 px/ms): 每 50px 一格
    // 快速 (>2 px/ms): 每 20px 一格
    const v = this.scrollVelocity;
    if (v < 0.3) return 60;        // 非常慢：每 60px 一次
    if (v < 0.8) return 45;        // 慢速：每 45px 一次
    if (v < 1.5) return 35;        // 中速：每 35px 一次
    return 25;                      // 快速：每 25px 一次
  }

  /**
   * 根据速度返回震动强度系数（0~1）
   * 速度快 → 震动略强（但有上限，不会太猛）
   */
  getIntensity() {
    const v = this.scrollVelocity;
    return Math.min(1.0, 0.3 + v * 0.3); // 0.3 ~ 1.0
  }
}

// 使用
new ScrollHapticController(trackpad);
```

---

### 3.5 键盘按键反馈（Keyboard）

**目标**：在虚拟键盘上打字时，每个按键按下给出一下脆脆的"嗒"——类似 MacBook 键盘的那种反馈。

**关键点**：
- 反馈要**极短极脆**（8ms），强调锐度而不是力度
- 必须在 keydown/touchstart 瞬间触发，不能有延迟
- 不要在长按某个键（重复输入）时每次都触发，第一次按下触发即可

```javascript
class KeyboardHaptic {
  constructor() {
    this.pressedKeys = new Set(); // 防止长按重复触发
  }

  /**
   * 绑定到键盘容器（事件委托方式，适用于动态渲染的键盘）
   * @param {HTMLElement} keyboardContainer - 键盘的 DOM 容器
   */
  bindTo(keyboardContainer) {
    // 使用 pointerdown 而不是 click，触发更早
    keyboardContainer.addEventListener('pointerdown', (e) => {
      const key = e.target.closest('.key'); // 假设每个按键有 .key 类
      if (!key) return;

      const keyId = key.dataset.keyId || key.textContent;
      if (this.pressedKeys.has(keyId)) return; // 已按下，跳过
      this.pressedKeys.add(keyId);

      // ✅ 触发按键反馈
      HapticEngine.keyPress();
    });

    keyboardContainer.addEventListener('pointerup', (e) => {
      const key = e.target.closest('.key');
      if (key) {
        this.pressedKeys.delete(key.dataset.keyId || key.textContent);
      }
    });

    keyboardContainer.addEventListener('pointercancel', (e) => {
      this.pressedKeys.clear();
    });
  }

  /**
   * 也可以绑定到物理键盘（如果有连接的话）
   */
  bindPhysicalKeyboard() {
    document.addEventListener('keydown', (e) => {
      if (e.repeat) return; // 忽略长按重复
      HapticEngine.keyPress();
    });
  }
}

// 使用
const keyboardHaptic = new KeyboardHaptic();
keyboardHaptic.bindTo(document.getElementById('virtual-keyboard'));
```

---

## 四、Apple 原生触觉模式参数参考

以下参数来自 Apple Core Haptics / AHAP 规范，供理解各反馈的"手感目标"。在 Web 中我们用振动时长来逼近这些感觉：

| 反馈场景           | 事件类型    | Intensity | Sharpness | 目标感觉               | Web 模拟方案                    |
| ------------------ | ----------- | --------- | --------- | ---------------------- | ------------------------------- |
| 单击（Tap）        | Transient   | 0.5       | 0.5       | 清脆的轻点             | `vibrate(10)`                   |
| 双击（Double Tap） | 2× Transient| 0.6       | 0.6       | 两下快速点击           | `vibrate([8, 40, 8])`           |
| 长按抓取           | Transient   | 0.7       | 0.3       | 沉稳的"抓住"感         | `vibrate(20)`                   |
| 拖拽释放           | Transient   | 0.4       | 0.7       | 轻快的"松开"感         | `vibrate(12)`                   |
| 滚轮段落（慢）     | Continuous  | 0.3       | 0.8       | 轻柔的咔哒             | `vibrate(6)`                    |
| 滚轮段落（快）     | Continuous  | 0.6       | 0.9       | 明显的快速咔哒         | `vibrate(14)`                   |
| 键盘按键           | Transient   | 0.4       | 0.8       | 脆脆的键盘敲击         | `vibrate(8)`                    |

---

## 五、调试与调优建议

### 5.1 振动时长的调优

振动的"手感"高度依赖具体手机硬件。不同手机的线性马达（LRA）响应速度差异很大：

| 手机类型           | 建议调整                                  |
| ------------------ | ----------------------------------------- |
| 高端 Android 旗舰  | 原始参数即可，LRA 响应快，10ms 足够脆     |
| 中低端 Android     | 单击建议加到 15~20ms，否则可能感觉不到     |
| iPhone（Audio hack）| 效果偏弱，可以尝试增大 duration           |

建议在设置中加入一个"震动强度"滑条，让用户自行调节：

```javascript
// 用户可调的振动强度系数
let hapticMultiplier = 1.0; // 0.5 ~ 2.0

// 在 HapticEngine 内部应用
function vibrateWithIntensity(baseDuration) {
  const adjusted = Math.round(baseDuration * hapticMultiplier);
  vibrateNative(Math.max(5, adjusted)); // 最少 5ms
}
```

### 5.2 iOS 的局限性与应对

iOS 上的 AudioContext hack 有以下局限：

1. **反馈偏弱**：Taptic Engine 的触发是被动的，不像原生 Core Haptics 可以精确控制
2. **需要用户先交互**：第一次触摸时解锁 AudioContext
3. **静音模式**：如果手机开了静音模式，部分 iOS 版本可能不触发
4. **不可靠**：这是非官方行为，Apple 随时可能修复掉

**建议**：在 iOS 上可以在设置中提供一个开关"触觉反馈（iOS 上效果有限）"，让用户知晓。

### 5.3 性能注意事项

```javascript
// ❌ 不要在 scroll/touchmove 中每次都调用振动
// 这会导致振动队列堆积，响应变差
element.addEventListener('touchmove', () => {
  navigator.vibrate(10); // 每帧都振动 → 灾难
});

// ✅ 应该通过节流 + 条件判断来控制
element.addEventListener('touchmove', throttle(() => {
  if (shouldTriggerTick()) {
    HapticEngine.scrollTick(intensity);
  }
}, 50));

// 节流函数
function throttle(fn, delay) {
  let last = 0;
  return function (...args) {
    const now = Date.now();
    if (now - last >= delay) {
      last = now;
      fn.apply(this, args);
    }
  };
}
```

### 5.4 取消振动的清理

在页面失焦或离开时，一定要清理残留的振动：

```javascript
document.addEventListener('visibilitychange', () => {
  if (document.hidden) {
    HapticEngine.stop(); // 停止所有振动
  }
});

window.addEventListener('beforeunload', () => {
  HapticEngine.stop();
});
```

---

## 六、总结：各场景 API 调用一览

| 场景           | 触发时机                           | API 调用                    | 振动参数              |
| -------------- | ---------------------------------- | --------------------------- | --------------------- |
| 单击           | touchend，距离<10px，时长<300ms    | `HapticEngine.tap()`        | 10ms 单段             |
| 双击           | 300ms 内两次点击                   | `HapticEngine.doubleTap()`  | [8, 40, 8] 双段       |
| 长按拖拽开始   | 持续触摸 400ms 不移动              | `HapticEngine.dragStart()`  | 20ms（更沉）          |
| 拖拽中         | 拖拽期间每隔 100ms                 | `HapticEngine.dragContinuous(20)` | 20ms 微弱脉冲    |
| 拖拽结束       | touchend（在拖拽状态下）           | `HapticEngine.dragEnd()`    | 12ms                  |
| 滚轮段落       | 每滚过动态间距（25~60px）          | `HapticEngine.scrollTick(v)`| 6~16ms（随速度变化）  |
| 键盘按键       | pointerdown on .key（非 repeat）   | `HapticEngine.keyPress()`   | 8ms 极脆              |

---

## 七、如果效果不够好——进阶方案

如果纯 Web 方案的反馈质感达不到要求，可以考虑以下进阶路线：

1. **Capacitor 混合方案**：将 Web 页面用 Capacitor 包装成原生 App，使用 `@capacitor/haptics` 插件直接调用 iOS Core Haptics / Android Haptic API，可以获得与原生 App 一致的反馈效果。

2. **TWA (Trusted Web Activity)**：将 PWA 通过 TWA 包装为 Android App，获得更好的振动控制能力。

3. **WebAssembly + Emscripten**：理论上可以通过 WASM 调用底层系统 API，但实际上浏览器沙箱限制了这个路径。

4. **WebSocket + 原生伴侣 App**：手机端运行一个轻量原生 App 负责触觉反馈，Web 页面通过 WebSocket 与之通信。

---

*文档最后更新：2026-06-10*
