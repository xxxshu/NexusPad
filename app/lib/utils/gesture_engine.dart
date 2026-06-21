import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';

import 'haptic.dart';

/// 手势模式（仅用于 UI 状态标签）
enum GestureMode { idle, singleFinger, scroll, pinch, drag }

/// 手指数据
class _Finger {
  double x, y;
  double startX, startY;
  _Finger(this.x, this.y) : startX = x, startY = y;
}

/// 回调
class GestureCallbacks {
  final void Function(int dx, int dy)? onMove;
  final void Function()? onClick;
  final void Function()? onDblClick;
  final void Function()? onRightClick;
  final void Function()? onMouseDown;
  final void Function()? onMouseUp;
  final void Function(int dx, int dy)? onScroll;
  final void Function(double m)? onPinch;
  final void Function(GestureMode mode)? onModeChange;
  final void Function(double x, double y)? onTapAt;

  const GestureCallbacks({
    this.onMove, this.onClick, this.onDblClick, this.onRightClick,
    this.onMouseDown, this.onMouseUp, this.onScroll, this.onPinch,
    this.onModeChange, this.onTapAt,
  });
}

/// 触控板手势引擎 v3 — 直接匹配网页版 app.js 逻辑
/// 删除了复杂状态机，改为直接在 move 事件中判定和处理
class GestureEngine {
  final GestureCallbacks callbacks;
  GestureEngine(this.callbacks);

  // ── 常量（与网页版完全一致） ──
  static const double _th = 8.0;
  static const int _longPressMs = 400;
  static const int _tapMaxMs = 250;
  static const int _dblTapTimeMs = 300;
  static const double _dblTapDistPx = 10.0;
  static const double _pinchTh = 0.08;
  static const double _pinchSendTh = 0.15; // 匹配网页版阈值
  static const double _inertiaRate = 0.998;
  static const double _inertiaStopTh = 0.5;
  // ignore: prefer_final_fields
  static double _scrollScale = 0.5; // 默认 50%
  static const double _scrollLinearTh = 8.0; // 中等速度以下都走线性
  // ignore: prefer_final_fields
  static double _moveScale = 1.5; // 默认鼠标灵敏度
  static const double _scrollTickDist = 50.0;
  static const int _scrollTickMinMs = 40;
  static const int _tapTimeTh = 300; // 双指点击时间
  static const double _tapMoveTh = 15.0; // 双指点击移动

  // ── 状态 ──
  GestureMode _mode = GestureMode.idle;
  final Map<int, _Finger> _fingers = {};

  // 单指
  double _startX = 0, _startY = 0;
  bool _moved = false;
  int _tStart = 0;
  bool _pressing = false;
  Timer? _longPressTimer;

  // 双击
  int _lastTapT = 0;
  double _lastTapX = 0, _lastTapY = 0;

  // 单指移动管线
  double _prevDx = 0, _prevDy = 0;
  double _smoothedSpeed = 0;
  int _lastMoveT = 0;
  double _mvAccX = 0, _mvAccY = 0;

  // 双指检测
  double _initialPinchDist = 0;
  double _twoFingerMovedDist = 0;
  int _detectStart = 0;
  // 质心位置跟踪（用于连续滚动增量）
  double _centroidX = 0, _centroidY = 0;

  // 缩放
  double _pinchLastDist = 0;

  // 滚动
  double _scrFracX = 0, _scrFracY = 0;
  int _accScrX = 0, _accScrY = 0;
  double _inertiaVelocity = 0;
  Timer? _inertiaTimer;
  int _lastScrT = 0;
  double _scrollTickAccDist = 0;
  int _lastScrollTickT = 0;

  GestureMode get mode => _mode;

  /// 设置滚动灵敏度 (0.1 ~ 1.0，默认 0.25)
  static void setScrollSensitivity(double value) {
    _scrollScale = value.clamp(0.1, 1.0);
  }
  /// 设置鼠标移动灵敏度 (0.5 ~ 3.0，默认 1.0)
  static void setMoveSensitivity(double value) {
    _moveScale = value.clamp(0.5, 3.0);
  }
  static double get scrollSensitivity => _scrollScale;
  static double get moveSensitivity => _moveScale;

  void _setMode(GestureMode m) {
    if (_mode != m) {
      _mode = m;
      callbacks.onModeChange?.call(m);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 事件入口
  // ═══════════════════════════════════════════════════════════════

  void handlePointerDown(PointerDownEvent e) {
    _fingers[e.pointer] = _Finger(e.position.dx, e.position.dy);
    _stopInertia();

    if (_fingers.length == 1) {
      _moved = false;
      _tStart = e.timeStamp.inMilliseconds;
      _startX = e.position.dx;
      _startY = e.position.dy;
      _prevDx = 0; _prevDy = 0;
      _smoothedSpeed = 0;
      _mvAccX = 0; _mvAccY = 0;
      _lastMoveT = e.timeStamp.inMilliseconds;
      _setMode(GestureMode.singleFinger);
      _longPressTimer?.cancel();
      _longPressTimer = Timer(Duration(milliseconds: _longPressMs), _onLongPress);
    } else if (_fingers.length == 2) {
      _longPressTimer?.cancel();
      if (_pressing) { _pressing = false; callbacks.onMouseUp?.call(); }
      // 进入双指检测
      _setMode(GestureMode.idle); // 等待判定
      _detectStart = e.timeStamp.inMilliseconds;
      _twoFingerMovedDist = 0;
      _initialPinchDist = _twoFingerDist();
      _pinchLastDist = _initialPinchDist;
      _scrFracX = 0; _scrFracY = 0;
      _accScrX = 0; _accScrY = 0;
      _lastScrT = e.timeStamp.inMilliseconds;
      _scrollTickAccDist = 0; _lastScrollTickT = 0;
    }
  }

  void handlePointerMove(PointerMoveEvent e) {
    final finger = _fingers[e.pointer];
    if (finger == null) return;

    final dx = e.position.dx - finger.x;
    final dy = e.position.dy - finger.y;
    finger.x = e.position.dx;
    finger.y = e.position.dy;
    final now = e.timeStamp.inMilliseconds;

    // ── 单指 ──
    if (_fingers.length == 1) {
      _processSingleFinger(dx, dy, now, e);
      return;
    }

    // ── 双指 ──
    if (_fingers.length < 2) return;

    // 更新双指移动距离
    final entries = _fingers.values.toList();
    final d0 = sqrt(pow(entries[0].x - entries[0].startX, 2) + pow(entries[0].y - entries[0].startY, 2));
    final d1 = sqrt(pow(entries[1].x - entries[1].startX, 2) + pow(entries[1].y - entries[1].startY, 2));
    _twoFingerMovedDist = max(d0, d1);

    // 判定阶段：尚未确定 scroll 或 pinch
    if (_mode == GestureMode.idle) {
      _detectTwoFingerGesture(now);
    }

    // ── 处理已确定的手势 ──
    if (_mode == GestureMode.scroll) {
      _processScroll(now);
    } else if (_mode == GestureMode.pinch) {
      _processPinch();
    }
  }

  void handlePointerUp(PointerUpEvent e) {
    final finger = _fingers[e.pointer];
    if (finger == null) return;
    final now = e.timeStamp.inMilliseconds;
    _fingers.remove(e.pointer);

    if (_fingers.isEmpty) {
      _longPressTimer?.cancel();

      switch (_mode) {
        case GestureMode.drag:
          _pressing = false;
          callbacks.onMouseUp?.call();
          Haptic.dragEnd();
          break;
        case GestureMode.scroll:
          _startInertia();
          break;
        case GestureMode.pinch:
          break;
        case GestureMode.idle:
          // 双指检测中抬起 → 可能是双指点击
          if (now - _detectStart < _tapTimeTh && _twoFingerMovedDist < _tapMoveTh) {
            callbacks.onRightClick?.call();
            Haptic.tap();
          }
          break;
        case GestureMode.singleFinger:
          if (!_moved && now - _tStart < _tapMaxMs) {
            _handleTap(now, finger.x, finger.y);
          }
          break;
      }
      _setMode(GestureMode.idle);
    }
  }

  void handlePointerCancel(PointerCancelEvent e) {
    _fingers.remove(e.pointer);
    if (_fingers.isEmpty) {
      _longPressTimer?.cancel();
      _stopInertia();
      if (_pressing) { _pressing = false; callbacks.onMouseUp?.call(); }
      _setMode(GestureMode.idle);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 单指移动
  // ═══════════════════════════════════════════════════════════════

  void _processSingleFinger(double dx, double dy, int now, PointerMoveEvent e) {
    if (!_moved) {
      final dist = sqrt(pow(e.position.dx - _startX, 2) + pow(e.position.dy - _startY, 2));
      if (dist > _th) { _moved = true; _longPressTimer?.cancel(); }
    }
    if (!_moved && _mode != GestureMode.drag) return;

    final sdx = 0.5 * dx + 0.5 * _prevDx;
    final sdy = 0.5 * dy + 0.5 * _prevDy;
    _prevDx = sdx; _prevDy = sdy;

    final dt = max(now - _lastMoveT, 1);
    _lastMoveT = now;
    final speed = sqrt(sdx * sdx + sdy * sdy) / dt;
    _smoothedSpeed = 0.3 * speed + 0.7 * _smoothedSpeed;
    final mult = _threeSegAccel(_smoothedSpeed);

    _mvAccX += sdx * mult * _moveScale;
    _mvAccY += sdy * mult * _moveScale;
    final ix = _mvAccX.truncate();
    final iy = _mvAccY.truncate();
    if (ix != 0 || iy != 0) {
      _mvAccX -= ix; _mvAccY -= iy;
      callbacks.onMove?.call(ix, iy);
    }
  }

  double _threeSegAccel(double vel) {
    if (vel < 0.5) return 1.0;
    if (vel < 2.0) return 1.0 + (vel - 0.5) * 0.8;
    return min(2.2 + (vel - 2.0) * 0.5, 5.2);
  }

  // ═══════════════════════════════════════════════════════════════
  // 双指手势判定（直接匹配网页版 detectGesture()）
  // ═══════════════════════════════════════════════════════════════

  void _detectTwoFingerGesture(int now) {
    final entries = _fingers.values.toList();
    if (entries.length < 2) return;
    final f0 = entries[0], f1 = entries[1];

    final dCurrent = sqrt(pow(f0.x - f1.x, 2) + pow(f0.y - f1.y, 2));
    final dInitial = _initialPinchDist;
    final distChange = dInitial > 0 ? (dCurrent - dInitial).abs() / dInitial : 0.0;

    // 中心移动
    final cdx = (f0.x + f1.x) / 2 - (f0.startX + f1.startX) / 2;
    final cdy = (f0.y + f1.y) / 2 - (f0.startY + f1.startY) / 2;
    final centroidDist = sqrt(cdx * cdx + cdy * cdy);

    // Pinch: 距离变化 > 8% 且主导
    final pinchDominant = distChange > _pinchTh &&
        (centroidDist < 5 || distChange * dInitial > centroidDist * 0.5);
    if (pinchDominant) {
      _setMode(GestureMode.pinch);
      _pinchLastDist = dCurrent;
      return;
    }

    // Scroll: 两指同向移动且中心移动 > TH
    final dot = (f0.x - f0.startX) * (f1.x - f1.startX) + (f0.y - f0.startY) * (f1.y - f1.startY);
    if (dot > 0 && (cdx.abs() > _th || cdy.abs() > _th)) {
      _setMode(GestureMode.scroll);
      // 初始化质心
      final c = _centroid();
      _centroidX = c.$1;
      _centroidY = c.$2;
      _scrFracX = 0; _scrFracY = 0; _accScrX = 0; _accScrY = 0;
      _lastScrT = now;
      _scrollTickAccDist = 0; _lastScrollTickT = 0;
      return;
    }

    // 超时默认滚动
    if (now - _detectStart > 250) {
      _setMode(GestureMode.scroll);
      final c = _centroid();
      _centroidX = c.$1;
      _centroidY = c.$2;
      _scrFracX = 0; _scrFracY = 0; _accScrX = 0; _accScrY = 0;
      _lastScrT = now;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 连续滚动（直接匹配网页版，每次 move 都处理）
  // ═══════════════════════════════════════════════════════════════

  void _processScroll(int now) {
    // 计算当前质心
    final c = _centroid();
    // 增量 = 当前质心 - 上次质心
    final rawDx = c.$1 - _centroidX;
    final rawDy = c.$2 - _centroidY;
    // 立即更新质心（下一个 move 事件用新值）
    _centroidX = c.$1;
    _centroidY = c.$2;

    // 取反 dy：手指上滑(y减小) → 负值 → 取反正值 → 页面向下滚
    final cdx = _scrollCurve(rawDx);
    final cdy = _scrollCurve(-rawDy);

    // 速度跟踪（惯性用）
    final scrDt = max(now - _lastScrT, 1);
    _lastScrT = now;
    final instantV = cdy / scrDt * 16;
    _inertiaVelocity = 0.4 * instantV + 0.6 * _inertiaVelocity;

    // 亚像素累加
    _scrFracX += cdx;
    _scrFracY += cdy;
    final ix = _scrFracX.truncate();
    final iy = _scrFracY.truncate();
    if (ix != 0 || iy != 0) {
      _scrFracX -= ix; _scrFracY -= iy;
      _accScrX += ix; _accScrY += iy;

      // 震动
      final tickDist = sqrt((ix * ix + iy * iy).toDouble());
      _scrollTickAccDist += tickDist;
      if (_scrollTickAccDist >= _scrollTickDist && now - _lastScrollTickT >= _scrollTickMinMs) {
        Haptic.scrollTick(min(1.0, _scrollTickAccDist / 200));
        _scrollTickAccDist = 0; _lastScrollTickT = now;
      }
      // 直接发送，不等 rAF（保证跟手）
      callbacks.onScroll?.call(_accScrX, _accScrY);
      _accScrX = 0; _accScrY = 0;
    }
  }

  /// 灵敏度与平滑的平衡：慢速直接线性，快速非线性曲线
  double _scrollCurve(double delta) {
    final absD = delta.abs();
    final sign = delta < 0 ? -1.0 : 1.0;
    // 慢速：直接线性缩放（保证细腻跟手）
    if (absD <= _scrollLinearTh) return delta * _scrollScale;
    // 快速：非线性曲线加速
    final curved = absD * (0.3 + 0.012 * absD);
    return sign * min(curved, absD * 3) * _scrollScale;
  }

  // ═══════════════════════════════════════════════════════════════
  // 连续缩放（直接匹配网页版）
  // ═══════════════════════════════════════════════════════════════

  void _processPinch() {
    final entries = _fingers.values.toList();
    if (entries.length < 2) return;
    final d = sqrt(pow(entries[0].x - entries[1].x, 2) + pow(entries[0].y - entries[1].y, 2));
    if (_pinchLastDist > 0) {
      // 从上次发送点累积到当前的总缩放量
      final ratio = log(d / _pinchLastDist);
      if (ratio.abs() > _pinchSendTh) {
        callbacks.onPinch?.call(ratio);
        _pinchLastDist = d; // 只在发送后更新基准
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 惯性滚动
  // ═══════════════════════════════════════════════════════════════

  void _startInertia() {
    if (_inertiaVelocity.abs() < _inertiaStopTh) return;
    _scrFracY = 0; _accScrY = 0;
    _inertiaTimer?.cancel();
    var lastT = DateTime.now().millisecondsSinceEpoch;
    _inertiaTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final dt = (now - lastT) / 1000.0;
      lastT = now;
      _inertiaVelocity *= pow(_inertiaRate, dt * 60);
      if (_inertiaVelocity.abs() < _inertiaStopTh) { _stopInertia(); return; }
      _scrFracY += _inertiaVelocity * dt * 60;
      final iy = _scrFracY.truncate();
      if (iy != 0) {
        _scrFracY -= iy; _accScrY += iy;
        callbacks.onScroll?.call(0, _accScrY);
        _accScrY = 0;
      }
    });
  }

  void _stopInertia() {
    _inertiaTimer?.cancel();
    _inertiaTimer = null;
    _inertiaVelocity = 0;
  }

  // ═══════════════════════════════════════════════════════════════
  // 长按 / 点击
  // ═══════════════════════════════════════════════════════════════

  void _onLongPress() {
    if (_moved || _mode != GestureMode.singleFinger) return;
    _pressing = true;
    _setMode(GestureMode.drag);
    callbacks.onMouseDown?.call();
    Haptic.dragStart();
  }

  void _handleTap(int now, double x, double y) {
    final dt = now - _lastTapT;
    final dd = sqrt(pow(x - _lastTapX, 2) + pow(y - _lastTapY, 2));
    if (_lastTapT > 0 && dt < _dblTapTimeMs && dd < _dblTapDistPx) {
      callbacks.onDblClick?.call();
      callbacks.onTapAt?.call(x, y);
      Haptic.doubleTap();
      _lastTapT = 0;
    } else {
      callbacks.onClick?.call();
      callbacks.onTapAt?.call(x, y);
      Haptic.tap();
      _lastTapT = now; _lastTapX = x; _lastTapY = y;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // 工具
  // ═══════════════════════════════════════════════════════════════

  double _twoFingerDist() {
    final entries = _fingers.values.toList();
    if (entries.length < 2) return 0;
    final d = sqrt(pow(entries[0].x - entries[1].x, 2) + pow(entries[0].y - entries[1].y, 2));
    return d.isFinite ? d : 0;
  }

  /// 计算两指中心点
  (double, double) _centroid() {
    final entries = _fingers.values.toList();
    if (entries.length < 2) return (0, 0);
    return (
      (entries[0].x + entries[1].x) / 2,
      (entries[0].y + entries[1].y) / 2,
    );
  }

  void dispose() {
    _longPressTimer?.cancel();
    _stopInertia();
  }
}
