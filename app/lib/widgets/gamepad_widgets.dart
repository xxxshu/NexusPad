import 'package:flutter/material.dart';

import '../utils/haptic.dart';

// ============================================================================
// Joystick Widget — 拖拽式虚拟摇杆
// ============================================================================

class JoystickWidget extends StatefulWidget {
  final double size;
  final void Function(double x, double y) onChange;
  final String? label;

  const JoystickWidget({
    super.key,
    required this.size,
    required this.onChange,
    this.label,
  });

  @override
  State<JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<JoystickWidget> {
  double _dx = 0, _dy = 0; // -1.0 ~ 1.0
  bool _active = false;
  int? _pointerId;

  double get _radius => widget.size / 2;
  double get _knobRadius => widget.size * 0.2;

  void _handlePointerDown(PointerDownEvent e) {
    if (_pointerId != null) return;
    _pointerId = e.pointer;
    _active = true;
    _updatePosition(e.localPosition);
    Haptic.dragStart();
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (e.pointer != _pointerId) return;
    _updatePosition(e.localPosition);
  }

  void _handlePointerUp(PointerUpEvent e) {
    if (e.pointer != _pointerId) return;
    _pointerId = null;
    setState(() {
      _dx = 0;
      _dy = 0;
      _active = false;
    });
    widget.onChange(0, 0);
    Haptic.dragEnd();
  }

  void _handlePointerCancel(PointerCancelEvent e) {
    if (e.pointer != _pointerId) return;
    _pointerId = null;
    setState(() {
      _dx = 0;
      _dy = 0;
      _active = false;
    });
    widget.onChange(0, 0);
  }

  void _updatePosition(Offset local) {
    final center = Offset(_radius, _radius);
    var delta = local - center;
    final dist = delta.distance;
    final maxDist = _radius - _knobRadius;

    if (dist > maxDist && maxDist > 0) {
      delta = delta * (maxDist / dist);
    }

    final nx = maxDist > 0 ? (delta.dx / maxDist).clamp(-1.0, 1.0) : 0.0;
    final ny = maxDist > 0 ? (delta.dy / maxDist).clamp(-1.0, 1.0) : 0.0;

    setState(() {
      _dx = nx;
      _dy = ny;
    });
    widget.onChange(nx, ny);
  }

  @override
  Widget build(BuildContext context) {
    final knobOffsetX = _dx * (_radius - _knobRadius);
    final knobOffsetY = _dy * (_radius - _knobRadius);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _JoystickPainter(
            dx: _dx,
            dy: _dy,
            active: _active,
            knobOffsetX: knobOffsetX,
            knobOffsetY: knobOffsetY,
            knobRadius: _knobRadius,
            label: widget.label,
          ),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final double dx, dy;
  final bool active;
  final double knobOffsetX, knobOffsetY;
  final double knobRadius;
  final String? label;

  _JoystickPainter({
    required this.dx,
    required this.dy,
    required this.active,
    required this.knobOffsetX,
    required this.knobOffsetY,
    required this.knobRadius,
    this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    // Outer ring (凹槽效果)
    final outerPaint = Paint()
      ..color = const Color(0xFF1e3352)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, outerPaint);

    // Inner shadow (inset effect)
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.inner, 4);
    canvas.drawCircle(center, outerRadius, shadowPaint);

    // Track groove ring
    final groovePaint = Paint()
      ..color = const Color(0xFF162840)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius * 0.75, groovePaint);

    // Knob (可拖拽圆点)
    final knobCenter = center + Offset(knobOffsetX, knobOffsetY);
    final knobPaint = Paint()
      ..color = active
          ? const Color(0xFF4a9eff)
          : const Color(0xFF8ab4e0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter, knobRadius, knobPaint);

    // Knob highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: active ? 0.35 : 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(knobCenter - Offset(0, knobRadius * 0.25), knobRadius * 0.55, highlightPaint);

    // Knob shadow
    final knobShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(knobCenter + const Offset(0, 2), knobRadius, knobShadowPaint);

    // Label text
    if (label != null) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.25),
            fontSize: size.width * 0.14,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) =>
      dx != old.dx || dy != old.dy || active != old.active;
}

// ============================================================================
// Gamepad Button Widget
// ============================================================================

class GamepadButton extends StatefulWidget {
  final String? label;
  final Widget? child;
  final double size;
  final Color color;
  final Color? bgColor;
  final void Function(bool pressed) onPressed;

  const GamepadButton({
    super.key,
    this.label,
    this.child,
    this.size = 52,
    this.color = Colors.white,
    this.bgColor,
    required this.onPressed,
  });

  @override
  State<GamepadButton> createState() => _GamepadButtonState();
}

class _GamepadButtonState extends State<GamepadButton> {
  bool _pressed = false;
  final Set<int> _pointers = {};

  void _onPointerDown(PointerDownEvent e) {
    _pointers.add(e.pointer);
    if (!_pressed) {
      setState(() => _pressed = true);
      widget.onPressed(true);
      Haptic.buttonPress();
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty && _pressed) {
      setState(() => _pressed = false);
      widget.onPressed(false);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty && _pressed) {
      setState(() => _pressed = false);
      widget.onPressed(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.bgColor ?? const Color(0xFF2a3f5f);

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _pressed
              ? bgColor.withValues(alpha: 0.8)
              : bgColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: _pressed
                ? widget.color.withValues(alpha: 0.6)
                : widget.color.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        transform: _pressed ? Matrix4.diagonal3Values(0.92, 0.92, 1.0) : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: Center(
          child: widget.child ??
              Text(
                widget.label ?? '',
                style: TextStyle(
                  color: widget.color,
                  fontSize: widget.size * 0.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
        ),
      ),
    );
  }
}

// ============================================================================
// D-Pad Widget — 十字键
// ============================================================================

class DpadWidget extends StatefulWidget {
  final double size;
  final void Function(int bit, bool pressed) onButton;

  const DpadWidget({
    super.key,
    this.size = 120,
    required this.onButton,
  });

  @override
  State<DpadWidget> createState() => _DpadWidgetState();
}

class _DpadWidgetState extends State<DpadWidget> {
  // Bits: 4=Up, 5=Down, 6=Left, 7=Right
  final Set<int> _activeDirections = {};
  final Set<int> _pointers = {};

  static const int _bitUp = 4;
  static const int _bitDown = 5;
  static const int _bitLeft = 6;
  static const int _bitRight = 7;

  void _updateDirections(Offset local) {
    final s = widget.size;
    final cx = s / 2;
    final cy = s / 2;
    final dx = local.dx - cx;
    final dy = local.dy - cy;

    // Calculate which quadrant the touch is in
    final newDirs = <int>{};

    // Dead zone in center
    final deadZone = s * 0.15;
    if (dx.abs() < deadZone && dy.abs() < deadZone) {
      // Center dead zone — no direction
    } else {
      // Determine primary axis
      if (dx.abs() > dy.abs()) {
        // Horizontal dominant
        if (dx < -deadZone) newDirs.add(_bitLeft);
        if (dx > deadZone) newDirs.add(_bitRight);
        // Also add vertical if significant
        if (dy.abs() > s * 0.25) {
          if (dy < 0) newDirs.add(_bitUp);
          if (dy > 0) newDirs.add(_bitDown);
        }
      } else {
        // Vertical dominant
        if (dy < -deadZone) newDirs.add(_bitUp);
        if (dy > deadZone) newDirs.add(_bitDown);
        // Also add horizontal if significant
        if (dx.abs() > s * 0.25) {
          if (dx < 0) newDirs.add(_bitLeft);
          if (dx > 0) newDirs.add(_bitRight);
        }
      }
    }

    // Release old, press new
    for (final d in _activeDirections.difference(newDirs)) {
      widget.onButton(d, false);
    }
    for (final d in newDirs.difference(_activeDirections)) {
      widget.onButton(d, true);
      Haptic.buttonPress();
    }
    _activeDirections.clear();
    _activeDirections.addAll(newDirs);
    setState(() {});
  }

  void _releaseAll() {
    for (final d in _activeDirections) {
      widget.onButton(d, false);
    }
    _activeDirections.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final armW = s * 0.3;
    final armH = s * 0.3;

    return SizedBox(
      width: s,
      height: s,
      child: Listener(
        onPointerDown: (e) {
          _pointers.add(e.pointer);
          _updateDirections(e.localPosition);
        },
        onPointerMove: (e) {
          if (_pointers.contains(e.pointer)) {
            _updateDirections(e.localPosition);
          }
        },
        onPointerUp: (e) {
          _pointers.remove(e.pointer);
          if (_pointers.isEmpty) _releaseAll();
        },
        onPointerCancel: (e) {
          _pointers.remove(e.pointer);
          if (_pointers.isEmpty) _releaseAll();
        },
        behavior: HitTestBehavior.opaque,
        child: CustomPaint(
          painter: _DpadPainter(
            activeDirections: _activeDirections,
            armW: armW,
            armH: armH,
          ),
        ),
      ),
    );
  }
}

class _DpadPainter extends CustomPainter {
  final Set<int> activeDirections;
  final double armW, armH;

  _DpadPainter({required this.activeDirections, required this.armW, required this.armH});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Cross shape
    final crossPaint = Paint()
      ..color = const Color(0xFF1e3352)
      ..style = PaintingStyle.fill;

    // Vertical arm
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: armW, height: r * 2),
        const Radius.circular(6),
      ),
      crossPaint,
    );
    // Horizontal arm
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 2, height: armH),
        const Radius.circular(6),
      ),
      crossPaint,
    );

    // Center circle
    canvas.drawCircle(Offset(cx, cy), armW * 0.45, Paint()..color = const Color(0xFF162840));

    // Active highlights
    final highlightPaint = Paint()..color = const Color(0xFF4a9eff).withValues(alpha: 0.5);
    const double arrowSize = 5;

    if (activeDirections.contains(4)) {
      // Up
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy - r * 0.5), width: armW - 4, height: r - 2),
          const Radius.circular(4),
        ),
        highlightPaint,
      );
    }
    if (activeDirections.contains(5)) {
      // Down
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy + r * 0.5), width: armW - 4, height: r - 2),
          const Radius.circular(4),
        ),
        highlightPaint,
      );
    }
    if (activeDirections.contains(6)) {
      // Left
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx - r * 0.5, cy), width: r - 2, height: armH - 4),
          const Radius.circular(4),
        ),
        highlightPaint,
      );
    }
    if (activeDirections.contains(7)) {
      // Right
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx + r * 0.5, cy), width: r - 2, height: armH - 4),
          const Radius.circular(4),
        ),
        highlightPaint,
      );
    }

    // Arrow indicators
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    // Up arrow
    final upPath = Path()
      ..moveTo(cx, cy - r * 0.7 - arrowSize)
      ..lineTo(cx - arrowSize, cy - r * 0.7 + arrowSize)
      ..lineTo(cx + arrowSize, cy - r * 0.7 + arrowSize)
      ..close();
    canvas.drawPath(upPath, arrowPaint);

    // Down arrow
    final downPath = Path()
      ..moveTo(cx, cy + r * 0.7 + arrowSize)
      ..lineTo(cx - arrowSize, cy + r * 0.7 - arrowSize)
      ..lineTo(cx + arrowSize, cy + r * 0.7 - arrowSize)
      ..close();
    canvas.drawPath(downPath, arrowPaint);

    // Left arrow
    final leftPath = Path()
      ..moveTo(cx - r * 0.7 - arrowSize, cy)
      ..lineTo(cx - r * 0.7 + arrowSize, cy - arrowSize)
      ..lineTo(cx - r * 0.7 + arrowSize, cy + arrowSize)
      ..close();
    canvas.drawPath(leftPath, arrowPaint);

    // Right arrow
    final rightPath = Path()
      ..moveTo(cx + r * 0.7 + arrowSize, cy)
      ..lineTo(cx + r * 0.7 - arrowSize, cy - arrowSize)
      ..lineTo(cx + r * 0.7 - arrowSize, cy + arrowSize)
      ..close();
    canvas.drawPath(rightPath, arrowPaint);

    // Border
    final borderPaint = Paint()
      ..color = const Color(0xFF2a4a70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 2, height: r * 2),
        const Radius.circular(10),
      ),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DpadPainter old) =>
      activeDirections != old.activeDirections;
}
