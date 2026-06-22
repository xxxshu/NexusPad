import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gamepad_layout.dart';
import '../models/protocol.dart';
import '../services/ws_service.dart';
import '../utils/neu_tokens.dart';
import 'gamepad_screen.dart' show TriggerBar, ShoulderBtn, FaceBtn;

/// 自定义布局运行界面（横屏）— 拟态风格
class CustomGamepadScreen extends StatefulWidget {
  final WsService wsService;
  final GamepadLayout layout;
  const CustomGamepadScreen({super.key, required this.wsService, required this.layout});

  @override
  State<CustomGamepadScreen> createState() => _CustomGamepadScreenState();
}

class _CustomGamepadScreenState extends State<CustomGamepadScreen> {
  double _lx = 0, _ly = 0, _rx = 0, _ry = 0;
  int _buttons = 0;
  int _lastSentButtons = -1;
  double _lastLx = -999, _lastLy = -999, _lastRx = -999, _lastRy = -999;
  Timer? _sendTimer;
  late final VoidCallback _wsListener;

  static const _buttonBits = {
    'a': 0, 'b': 1, 'x': 2, 'y': 3,
    'up': 4, 'down': 5, 'left': 6, 'right': 7,
    'lb': 8, 'rb': 9, 'lt': 8, 'rt': 9,
    'ls': 10, 'rs': 11,
    'back': 12, 'menu': 13, 'guide': 14,
  };

  // Face button color map (Xbox defaults for custom layout)
  static const _faceColors = {
    'a': Color(0xFF43A047), 'b': Color(0xFFE53935),
    'x': Color(0xFF1B8EF2), 'y': Color(0xFFF5A623),
  };

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _wsListener = () {
      if (!mounted) return;
      final ws = widget.wsService;
      if (!ws.isConnected && ws.state != ConnState.waitingAuth) _showDisconnect();
    };
    widget.wsService.addListener(_wsListener);
    _sendTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _sendState());
    _loadPenPosition();
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    widget.wsService.removeListener(_wsListener);
    widget.wsService.sendMessage(CGamepadDisconnect());
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _sendState() {
    if (_lx == _lastLx && _ly == _lastLy &&
        _rx == _lastRx && _ry == _lastRy &&
        _buttons == _lastSentButtons) {
      return;
    }
    widget.wsService.sendBinaryMsg(CGamepadState(_lx, _ly, _rx, _ry, 0, 0, _buttons));
    _lastLx = _lx; _lastLy = _ly;
    _lastRx = _rx; _lastRy = _ry;
    _lastSentButtons = _buttons;
  }

  void _setButton(String? id, bool pressed) {
    if (id == null) return;
    final bit = _buttonBits[id];
    if (bit == null) return;
    setState(() {
      if (pressed) { _buttons |= (1 << bit); }
      else { _buttons &= ~(1 << bit); }
    });
    debugPrint('CustomGamepad: button $id bit=$bit pressed=$pressed buttons=$_buttons');
  }

  void _showDisconnect() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('连接断开'),
        content: const Text('与桌面端的连接已断开'),
        actions: [
          TextButton(
            onPressed: () { Navigator.of(ctx).pop(); Navigator.of(context).popUntil((r) => r.isFirst); },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _exitCustom() {
    widget.wsService.sendMessage(CGamepadDisconnect());
    Navigator.of(context).pop();
  }

  Future<void> _loadPenPosition() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _penX = prefs.getDouble('custom_pen_x') ?? 0.5;
      _penY = prefs.getDouble('custom_pen_y') ?? 0.12;
    });
  }

  Future<void> _savePenPosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('custom_pen_x', _penX);
    await prefs.setDouble('custom_pen_y', _penY);
  }

  // 笔按钮位置 (屏幕比例)
  double _penX = 0.5; // center
  double _penY = 0.12; // near top

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final penSize = screenH * 0.12;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment(-0.8, -1.0),
            end: Alignment(0.6, 1.0),
            colors: [Color(0xFFD8EAF8), Color(0xFFC3D8EC)],
          ),
        ),
        child: Stack(
          children: [
            for (int i = 0; i < widget.layout.elements.length; i++)
              _buildElement(i, screenW, screenH),
            // 强制笔按钮 (可拖动，长按退出)
            _buildPenButton(screenW, screenH, penSize),
          ],
        ),
      ),
    );
  }

  Widget _buildPenButton(double screenW, double screenH, double size) {
    return Positioned(
      left: _penX * screenW - size / 2,
      top: _penY * screenH - size / 2,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _penX = (_penX + d.delta.dx / screenW).clamp(0.05, 0.95);
            _penY = (_penY + d.delta.dy / screenH).clamp(0.05, 0.95);
          });
        },
        onPanEnd: (_) => _savePenPosition(),
        onLongPress: _exitCustom,
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [neuAc, Color(0xFF5EC3FF)],
            ),
            boxShadow: [
              BoxShadow(color: neuAg, blurRadius: 12),
              const BoxShadow(color: neuDs, blurRadius: 5, offset: Offset(3, 3)),
              BoxShadow(color: neuLs.withValues(alpha: 0.9), blurRadius: 2.5, offset: const Offset(-2, -2)),
            ],
          ),
          child: const Center(child: Icon(Icons.edit, color: Colors.white, size: 20)),
        ),
      ),
    );
  }

  Widget _buildElement(int index, double screenW, double screenH) {
    final el = widget.layout.elements[index];
    final size = el.size * screenH;
    final centerX = el.x * screenW;
    final centerY = el.y * screenH;

    // 摇杆 → 拟态摇杆
    if (el.type == 'joystick') {
      return Positioned(
        left: centerX - size / 2,
        top: centerY - size / 2,
        child: _NeumorphicJoystick(
          size: size,
          label: el.stickSide == 'left' ? 'L' : 'R',
          onChanged: (x, y) {
            setState(() {
              if (el.stickSide == 'left') { _lx = x; _ly = y; }
              else { _rx = x; _ry = y; }
            });
          },
        ),
      );
    }

    // 触控板 → 拟态触控板
    if (el.type == 'touchpad') {
      final w = size * 1.5;
      final h = size;
      return Positioned(
        left: centerX - w / 2,
        top: centerY - h / 2,
        child: _NeumorphicTouchpad(
          width: w, height: h,
          sensitivity: el.sensitivity ?? 1.0,
          onChanged: (x, y) {
            setState(() {
              if (el.mapTo == 'left') { _lx = x; _ly = y; }
              else { _rx = x; _ry = y; }
            });
          },
        ),
      );
    }

    // 十字键 (单个方向按钮)
    if (el.type == 'button' && el.buttonId != null &&
        ['up', 'down', 'left', 'right'].contains(el.buttonId)) {
      const dirBits = {'up': 4, 'down': 5, 'left': 6, 'right': 7};
      const dirIcons = {'up': '▲', 'down': '▼', 'left': '◀', 'right': '▶'};
      final bit = dirBits[el.buttonId]!;
      return Positioned(
        left: centerX - size / 2,
        top: centerY - size / 2,
        child: _NeumorphicCircleBtn(
          size: size,
          label: dirIcons[el.buttonId]!,
          onPressed: (v) {
            setState(() {
              if (v) { _buttons |= (1 << bit); }
              else { _buttons &= ~(1 << bit); }
            });
          },
        ),
      );
    }

    // 肩键
    if (el.type == 'button' && (el.buttonId == 'lb' || el.buttonId == 'rb')) {
      return Positioned(
        left: centerX - 38, top: centerY - 15,
        child: ShoulderBtn(
          label: el.label ?? el.buttonId!.toUpperCase(),
          onChanged: (v) => _setButton(el.buttonId, v),
        ),
      );
    }

    // 扳机
    if (el.type == 'button' && (el.buttonId == 'lt' || el.buttonId == 'rt')) {
      final isLeft = el.buttonId == 'lt';
      return Positioned(
        left: isLeft ? centerX - size : centerX,
        top: centerY - 21,
        child: SizedBox(
          width: size,
          child: TriggerBar(
            label: el.label ?? el.buttonId!.toUpperCase(),
            align: isLeft ? 'left' : 'right',
            onChanged: (v) {
              // 扳机映射到对应肩键位
              _setButton(el.buttonId, v > 0.5);
            },
          ),
        ),
      );
    }

    // 面部按钮 (A/B/X/Y) → 彩色圆形
    if (el.type == 'button' && _faceColors.containsKey(el.buttonId)) {
      return Positioned(
        left: centerX - size / 2,
        top: centerY - size / 2,
        child: FaceBtn(
          label: el.label ?? el.buttonId!.toUpperCase(),
          color: _faceColors[el.buttonId]!,
          size: size,
          onChanged: (v) => _setButton(el.buttonId, v),
        ),
      );
    }

    // 默认按钮 → 拟态圆形按钮
    return Positioned(
      left: centerX - size / 2,
      top: centerY - size / 2,
      child: _NeumorphicCircleBtn(
        size: size,
        label: el.label ?? el.buttonId ?? '?',
        onPressed: (v) => _setButton(el.buttonId, v),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════════
//  Custom layout neumorphic widgets
// ═══════════════════════════════════════════════════════════════════════════════════

/// 拟态摇杆 (custom layout 用)
class _NeumorphicJoystick extends StatefulWidget {
  final double size;
  final String label;
  final void Function(double x, double y) onChanged;
  const _NeumorphicJoystick({required this.size, required this.label, required this.onChanged});

  @override
  State<_NeumorphicJoystick> createState() => _NeumorphicJoystickState();
}

class _NeumorphicJoystickState extends State<_NeumorphicJoystick> {
  double _dx = 0, _dy = 0;
  bool _active = false;
  int? _pid;
  final _key = GlobalKey();

  double get _maxR => widget.size * 0.27;

  void _update(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final center = box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2));
    var dx = global.dx - center.dx;
    var dy = global.dy - center.dy;
    final dist = Offset(dx, dy).distance;
    if (dist > _maxR) { dx = dx / dist * _maxR; dy = dy / dist * _maxR; }
    setState(() { _dx = dx; _dy = dy; });
    widget.onChanged(dx / _maxR, dy / _maxR);
  }

  void _release() {
    _pid = null;
    setState(() { _active = false; _dx = 0; _dy = 0; });
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Listener(
        key: _key,
        onPointerDown: (e) { _pid = e.pointer; setState(() => _active = true); _update(e.position); },
        onPointerMove: (e) { if (e.pointer == _pid) _update(e.position); },
        onPointerUp: (e) { if (e.pointer == _pid) _release(); },
        onPointerCancel: (e) { if (e.pointer == _pid) _release(); },
        child: Container(
          width: s, height: s,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: neuBg,
            boxShadow: [
              const BoxShadow(color: neuDs, blurRadius: 5, offset: Offset(4, 4)),
              BoxShadow(color: neuLs.withValues(alpha: 0.9), blurRadius: 2.5, offset: const Offset(-3, -3)),
            ],
          ),
          child: Center(child: Container(
            width: s * 0.78, height: s * 0.78,
            // Groove: 凹陷 — 左上阴影, 右下高亮; 高亮模糊=阴影一半
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: neuBg,
              boxShadow: [
                BoxShadow(color: neuLs.withValues(alpha: 0.9), blurRadius: 1.5, blurStyle: BlurStyle.inner, offset: const Offset(1, 1)),
                const BoxShadow(color: neuDs, blurRadius: 3, blurStyle: BlurStyle.inner, offset: Offset(-1, -1)),
              ],
            ),
            child: Center(child: AnimatedContainer(
              duration: _active ? Duration.zero : const Duration(milliseconds: 220),
              curve: _active ? Curves.linear : const Cubic(0.34, 1.56, 0.64, 1),
              width: s * 0.47, height: s * 0.47,
              transform: Matrix4.translationValues(_dx * 0.65, _dy * 0.65, 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: _active
                    ? const LinearGradient(begin: Alignment(-0.6, -0.8), end: Alignment(0.8, 0.6), colors: [neuAc, Color(0xFF60C3FF)])
                    : null,
                color: _active ? null : neuBg,
                boxShadow: _active
                    ? [BoxShadow(color: neuAg, blurRadius: 9), const BoxShadow(color: neuDs, blurRadius: 2, offset: Offset(2, 2))]
                    : [const BoxShadow(color: neuDs, blurRadius: 5, offset: Offset(4, 4)), BoxShadow(color: neuLs.withValues(alpha: 0.9), blurRadius: 2.5, offset: const Offset(-3, -3))],
              ),
            )),
          )),
        ),
      ),
      const SizedBox(height: 6),
      Text(widget.label, style: const TextStyle(fontSize: 9, color: neuMuted, fontWeight: FontWeight.w700, letterSpacing: 0.09)),
    ]);
  }
}

/// 拟态触控板 (custom layout 用)
class _NeumorphicTouchpad extends StatefulWidget {
  final double width, height;
  final double sensitivity;
  final void Function(double x, double y) onChanged;
  const _NeumorphicTouchpad({required this.width, required this.height, required this.sensitivity, required this.onChanged});

  @override
  State<_NeumorphicTouchpad> createState() => _NeumorphicTouchpadState();
}

class _NeumorphicTouchpadState extends State<_NeumorphicTouchpad> {
  int? _pid;

  void _update(Offset local) {
    final cx = widget.width / 2;
    final cy = widget.height / 2;
    final nx = ((local.dx - cx) / cx * widget.sensitivity).clamp(-1.0, 1.0);
    final ny = ((local.dy - cy) / cy * widget.sensitivity).clamp(-1.0, 1.0);
    widget.onChanged(nx, ny);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) { _pid = e.pointer; _update(e.localPosition); },
      onPointerMove: (e) { if (e.pointer == _pid) _update(e.localPosition); },
      onPointerUp: (e) { if (e.pointer == _pid) { _pid = null; widget.onChanged(0, 0); } },
      onPointerCancel: (e) { if (e.pointer == _pid) { _pid = null; widget.onChanged(0, 0); } },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          color: neuBg, borderRadius: BorderRadius.circular(10),
          boxShadow: [
            const BoxShadow(color: neuDs, blurRadius: 5, offset: Offset(4, 4)),
            BoxShadow(color: neuLs.withValues(alpha: 0.9), blurRadius: 2.5, offset: const Offset(-3, -3)),
          ],
        ),
        child: Center(child: Icon(Icons.touch_app, color: neuMuted.withValues(alpha: 0.5), size: 24)),
      ),
    );
  }
}

/// 拟态圆形按钮 (custom layout 通用)
class _NeumorphicCircleBtn extends StatefulWidget {
  final double size;
  final String label;
  final ValueChanged<bool> onPressed;
  const _NeumorphicCircleBtn({required this.size, required this.label, required this.onPressed});

  @override
  State<_NeumorphicCircleBtn> createState() => _NeumorphicCircleBtnState();
}

class _NeumorphicCircleBtnState extends State<_NeumorphicCircleBtn> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _active = true); widget.onPressed(true); },
      onTapUp: (_) { setState(() => _active = false); widget.onPressed(false); },
      onTapCancel: () { setState(() => _active = false); widget.onPressed(false); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size, height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active ? neuAc : neuBg,
          boxShadow: _active
              ? [BoxShadow(color: neuAg, blurRadius: 9), const BoxShadow(color: Color(0x2E000000), blurRadius: 5, offset: Offset(2, 2))]
              : [const BoxShadow(color: neuDs, blurRadius: 5, offset: Offset(4, 4)),
                 BoxShadow(color: neuLs.withValues(alpha: 0.9), blurRadius: 2.5, offset: const Offset(-3, -3))],
        ),
        child: Center(child: Text(widget.label, style: TextStyle(
          fontSize: widget.size * 0.25, fontWeight: FontWeight.w700,
          color: _active ? Colors.white : neuMuted,
        ))),
      ),
    );
  }
}
