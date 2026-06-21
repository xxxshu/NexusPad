import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';
import '../services/ws_service.dart';

/// 拟态风格手柄主界面 (横屏)
class GamepadScreen extends StatefulWidget {
  final WsService wsService;
  final String mode; // "xbox" | "ps"
  const GamepadScreen({super.key, required this.wsService, required this.mode});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  // 摇杆状态 -1~1
  double _lx = 0, _ly = 0, _rx = 0, _ry = 0;
  // 扳机状态 0~1
  double _lt = 0, _rt = 0;
  // 按钮位掩码
  int _buttons = 0;
  // 上次发送 (变化检测)
  int _lastSentButtons = -1;
  double _lastLx = -999, _lastLy = -999, _lastRx = -999, _lastRy = -999;
  double _lastLt = -1, _lastRt = -1;

  Timer? _sendTimer;
  late final VoidCallback _wsListener;

  bool get _isXbox => widget.mode == 'xbox';

  // 按钮位定义
  static const int _bitA = 0, _bitB = 1, _bitX = 2, _bitY = 3;
  static const int _bitLB = 8, _bitRB = 9, _bitLS = 10, _bitRS = 11;
  static const int _bitBack = 12, _bitMenu = 13, _bitGuide = 14;

  // 长按退出
  Timer? _guideTimer;
  static const _guideExitDuration = Duration(seconds: 2);

  // ─── Figma Make 设计令牌 ──────────────────────────────────────────────────────
  static const _bg    = Color(0xFFD3E4F3);
  static const _ls    = Color(0xE6FFFFFF); // rgba(255,255,255,0.90)
  static const _ds    = Color(0xFFA9BCCE);
  static const _ac    = Color(0xFF1B8EF2);
  static const _ag    = Color(0x4D1B8EF2); // rgba(27,142,242,0.30)

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
      if (!ws.isConnected && ws.state != ConnState.waitingAuth) {
        _showDisconnect();
      }
    };
    widget.wsService.addListener(_wsListener);

    _sendTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _sendState());
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _guideTimer?.cancel();
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
        _lt == _lastLt && _rt == _lastRt &&
        _buttons == _lastSentButtons) {
      return;
    }

    widget.wsService.sendMessage(
      CGamepadState(_lx, _ly, _rx, _ry, _lt, _rt, _buttons),
    );

    _lastLx = _lx; _lastLy = _ly;
    _lastRx = _rx; _lastRy = _ry;
    _lastLt = _lt; _lastRt = _rt;
    _lastSentButtons = _buttons;
  }

  void _setButton(int bit, bool pressed) {
    setState(() {
      if (pressed) {
        _buttons |= (1 << bit);
      } else {
        _buttons &= ~(1 << bit);
      }
    });
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
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _exitGamepad() {
    _guideTimer?.cancel();
    _guideTimer = null;
    widget.wsService.sendMessage(CGamepadDisconnect());
    Navigator.of(context).pop();
  }

  String _shoulderLabel(bool isLeft) => _isXbox ? (isLeft ? 'LB' : 'RB') : (isLeft ? 'L1' : 'R1');
  String _triggerLabel(bool isLeft)  => _isXbox ? (isLeft ? 'LT' : 'RT') : (isLeft ? 'L2' : 'R2');
  String _stickLabel(bool isLeft)    => _isXbox ? (isLeft ? 'LS' : 'RS') : (isLeft ? 'L3' : 'R3');

  // ─── UI 构建 ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          // 扳机行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              children: [
                Expanded(child: _TriggerBar(label: _triggerLabel(true), align: 'left',
                  onChanged: (v) => setState(() => _lt = v))),
                const SizedBox(width: 6),
                Expanded(child: _TriggerBar(label: _triggerLabel(false), align: 'right',
                  onChanged: (v) => setState(() => _rt = v))),
              ],
            ),
          ),
          // 肩键行
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ShoulderBtn(label: _shoulderLabel(true),  onChanged: (v) => _setButton(_bitLB, v)),
                _ShoulderBtn(label: _shoulderLabel(false), onChanged: (v) => _setButton(_bitRB, v)),
              ],
            ),
          ),
          // 主控制区
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: _isXbox ? _buildXboxLayout() : _buildPS5Layout(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Xbox 360 布局 ───────────────────────────────────────────────────────────
  // Figma: Row1[LS, center, ABXY], Row2[DPad, center, RS]
  Widget _buildXboxLayout() {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final jsSize  = (h * 0.36).clamp(70.0, 110.0);
        final fbSize  = (h * 0.115).clamp(36.0, 48.0);
        final dpSize  = (h * 0.29).clamp(60.0, 95.0);
        final cnSize  = (h * 0.10).clamp(30.0, 40.0);
        final hmSize  = (h * 0.16).clamp(42.0, 56.0);

        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _Joystick(size: jsSize, label: _stickLabel(true),
                    onChanged: (x, y) => setState(() { _lx = x; _ly = y; }),
                    onStickPress: (v) => _setButton(_bitLS, v))),
                  SizedBox(
                    width: 72,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CenterBtn(label: 'VIEW', size: cnSize,
                          onChanged: (v) => _setButton(_bitBack, v)),
                        const Spacer(),
                        _homeBtn(size: hmSize, icon: '⊞', onDown: () => _setButton(_bitGuide, true), onUp: () => _setButton(_bitGuide, false)),
                        const Spacer(),
                        _CenterBtn(label: 'MENU', size: cnSize,
                          onChanged: (v) => _setButton(_bitMenu, v)),
                      ],
                    ),
                  ),
                  Expanded(child: _xboxFace(size: fbSize)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _DPadWidget(size: dpSize, onButton: _setButton)),
                  const SizedBox(width: 72),
                  Expanded(child: _Joystick(size: jsSize, label: _stickLabel(false),
                    onChanged: (x, y) => setState(() { _rx = x; _ry = y; }),
                    onStickPress: (v) => _setButton(_bitRS, v))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── PS5 布局 ────────────────────────────────────────────────────────────────
  // Figma: Row1[DPad, center, FaceBtns], Row2[LS, center, RS]
  Widget _buildPS5Layout() {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final jsSize  = (h * 0.36).clamp(70.0, 110.0);
        final fbSize  = (h * 0.115).clamp(36.0, 48.0);
        final dpSize  = (h * 0.29).clamp(60.0, 95.0);
        final cnSize  = (h * 0.095).clamp(28.0, 38.0);
        final hmSize  = (h * 0.15).clamp(40.0, 54.0);
        final tpW     = (h * 0.18).clamp(48.0, 64.0);
        final tpH     = (h * 0.11).clamp(30.0, 42.0);

        return Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _DPadWidget(size: dpSize, onButton: _setButton)),
                  SizedBox(
                    width: 76,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CenterBtn(label: 'CREATE', size: cnSize,
                          onChanged: (v) => _setButton(_bitBack, v)),
                        const SizedBox(height: 4),
                        _TouchpadBtn(width: tpW, height: tpH,
                          onChanged: (v) => _setButton(_bitMenu, v)),
                        const SizedBox(height: 4),
                        _homeBtn(size: hmSize, icon: 'PS', onDown: () => _setButton(_bitGuide, true), onUp: () => _setButton(_bitGuide, false)),
                        const SizedBox(height: 4),
                        _CenterBtn(label: 'OPTIONS', size: cnSize,
                          onChanged: (v) => _setButton(_bitMenu, v)),
                      ],
                    ),
                  ),
                  Expanded(child: _ps5Face(size: fbSize)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _Joystick(size: jsSize, label: _stickLabel(true),
                    onChanged: (x, y) => setState(() { _lx = x; _ly = y; }),
                    onStickPress: (v) => _setButton(_bitLS, v))),
                  const SizedBox(width: 76),
                  Expanded(child: _Joystick(size: jsSize, label: _stickLabel(false),
                    onChanged: (x, y) => setState(() { _rx = x; _ry = y; }),
                    onStickPress: (v) => _setButton(_bitRS, v))),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Xbox 面部按钮簇 ─────────────────────────────────────────────────────────
  Widget _xboxFace({required double size}) {
    return _FaceCluster(
      btnSize: size,
      top: _FaceBtn(label: 'Y', color: const Color(0xFFF5A623), size: size, onChanged: (v) => _setButton(_bitY, v)),
      left: _FaceBtn(label: 'X', color: const Color(0xFF1B8EF2), size: size, onChanged: (v) => _setButton(_bitX, v)),
      right: _FaceBtn(label: 'B', color: const Color(0xFFE53935), size: size, onChanged: (v) => _setButton(_bitB, v)),
      bottom: _FaceBtn(label: 'A', color: const Color(0xFF43A047), size: size, onChanged: (v) => _setButton(_bitA, v)),
    );
  }

  // ─── PS5 面部按钮簇 ─────────────────────────────────────────────────────────
  Widget _ps5Face({required double size}) {
    return _FaceCluster(
      btnSize: size,
      top: _FaceBtn(label: '△', color: const Color(0xFF5CC49A), size: size, onChanged: (v) => _setButton(_bitY, v)),
      left: _FaceBtn(label: '□', color: const Color(0xFFC46BC4), size: size, onChanged: (v) => _setButton(_bitX, v)),
      right: _FaceBtn(label: '○', color: const Color(0xFFE06060), size: size, onChanged: (v) => _setButton(_bitB, v)),
      bottom: _FaceBtn(label: '✕', color: const Color(0xFF6EA8DE), size: size, onChanged: (v) => _setButton(_bitA, v)),
    );
  }

  // ─── Home 按钮 (长按退出) ─────────────────────────────────────────────────────
  Widget _homeBtn({
    required double size,
    required String icon,
    required VoidCallback onDown,
    required VoidCallback onUp,
  }) {
    return GestureDetector(
      onTapDown: (_) {
        onDown();
        _guideTimer?.cancel();
        _guideTimer = Timer(_guideExitDuration, _exitGamepad);
      },
      onTapUp: (_) {
        onUp();
        _guideTimer?.cancel();
        _guideTimer = null;
      },
      onTapCancel: () {
        onUp();
        _guideTimer?.cancel();
        _guideTimer = null;
      },
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [_ac, Color(0xFF5EC3FF)],
          ),
          boxShadow: [
            BoxShadow(color: _ag, blurRadius: 24, spreadRadius: 0),
            const BoxShadow(color: _ds, blurRadius: 9, offset: Offset(3, 3)),
            BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 6, offset: const Offset(-2, -2)),
          ],
        ),
        child: Center(
          child: Text(icon, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  拟态组件
// ═══════════════════════════════════════════════════════════════════════════════

class _TriggerBar extends StatefulWidget {
  final String label;
  final String align; // "left" | "right"
  final ValueChanged<double> onChanged;
  const _TriggerBar({required this.label, required this.align, required this.onChanged});

  @override
  State<_TriggerBar> createState() => _TriggerBarState();
}

class _TriggerBarState extends State<_TriggerBar> {
  bool _active = false;
  static const _bg = Color(0xFFD3E4F3);
  static const _ac = Color(0xFF1B8EF2);
  static const _ds = Color(0xFFA9BCCE);
  static const _ls = Color(0xE6FFFFFF);
  static const _muted = Color(0xFF6A8EAA);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _active = true); widget.onChanged(1.0); },
      onTapUp: (_) { setState(() => _active = false); widget.onChanged(0.0); },
      onTapCancel: () { setState(() => _active = false); widget.onChanged(0.0); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 42,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(widget.align == 'left' ? 10 : 4),
            bottomLeft: Radius.circular(widget.align == 'left' ? 10 : 4),
            topRight: Radius.circular(widget.align == 'right' ? 10 : 4),
            bottomRight: Radius.circular(widget.align == 'right' ? 10 : 4),
          ),
          boxShadow: _active
              ? [
                  const BoxShadow(color: _ds, blurRadius: 8, offset: Offset(3, 3)),
                  BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 6, offset: const Offset(-2, -2)),
                ]
              : [
                  const BoxShadow(color: _ds, blurRadius: 10, offset: Offset(4, 4)),
                  BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 9, offset: const Offset(-3, -3)),
                ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_active)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(widget.align == 'left' ? 10 : 4),
                      bottomLeft: Radius.circular(widget.align == 'left' ? 10 : 4),
                      topRight: Radius.circular(widget.align == 'right' ? 10 : 4),
                      bottomRight: Radius.circular(widget.align == 'right' ? 10 : 4),
                    ),
                    gradient: widget.align == 'left'
                        ? const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xB31B8EF2), Color(0x001B8EF2)])
                        : const LinearGradient(begin: Alignment.centerRight, end: Alignment.centerLeft, colors: [Color(0xB31B8EF2), Color(0x001B8EF2)]),
                  ),
                ),
              ),
            Text(widget.label, style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: _active ? _ac : _muted,
              letterSpacing: 0.08,
            )),
          ],
        ),
      ),
    );
  }
}

class _ShoulderBtn extends StatefulWidget {
  final String label;
  final ValueChanged<bool> onChanged;
  const _ShoulderBtn({required this.label, required this.onChanged});

  @override
  State<_ShoulderBtn> createState() => _ShoulderBtnState();
}

class _ShoulderBtnState extends State<_ShoulderBtn> {
  bool _active = false;
  static const _bg = Color(0xFFD3E4F3);
  static const _ac = Color(0xFF1B8EF2);
  static const _ag = Color(0x4D1B8EF2);
  static const _ds = Color(0xFFA9BCCE);
  static const _ls = Color(0xE6FFFFFF);
  static const _muted = Color(0xFF6A8EAA);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _active = true); widget.onChanged(true); },
      onTapUp: (_) { setState(() => _active = false); widget.onChanged(false); },
      onTapCancel: () { setState(() => _active = false); widget.onChanged(false); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 76, height: 30,
        decoration: BoxDecoration(
          color: _active ? _ac : _bg,
          borderRadius: BorderRadius.circular(8),
          boxShadow: _active
              ? [
                  BoxShadow(color: _ag, blurRadius: 18, spreadRadius: 0),
                  const BoxShadow(color: Color(0x2E000000), blurRadius: 5, offset: Offset(2, 2)),
                ]
              : [
                  const BoxShadow(color: _ds, blurRadius: 10, offset: Offset(4, 4)),
                  BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 9, offset: const Offset(-3, -3)),
                ],
        ),
        child: Center(
          child: Text(widget.label, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: _active ? Colors.white : _muted,
            letterSpacing: 0.07,
          )),
        ),
      ),
    );
  }
}

class _Joystick extends StatefulWidget {
  final double size;
  final String label;
  final void Function(double x, double y) onChanged;
  final ValueChanged<bool> onStickPress;
  const _Joystick({required this.size, required this.label, required this.onChanged, required this.onStickPress});

  @override
  State<_Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<_Joystick> {
  double _dx = 0, _dy = 0;
  bool _active = false;
  int? _pointerId;
  final _key = GlobalKey();
  static const _bg  = Color(0xFFD3E4F3);
  static const _ac  = Color(0xFF1B8EF2);
  static const _ag  = Color(0x4D1B8EF2);
  static const _ds  = Color(0xFFA9BCCE);
  static const _ls  = Color(0xE6FFFFFF);
  static const _muted = Color(0xFF6A8EAA);

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
    _pointerId = null;
    setState(() { _active = false; _dx = 0; _dy = 0; });
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerDown: (e) {
            _pointerId = e.pointer;
            setState(() => _active = true);
            _update(e.position);
          },
          onPointerMove: (e) { if (e.pointer == _pointerId) _update(e.position); },
          onPointerUp: (e) { if (e.pointer == _pointerId) _release(); },
          onPointerCancel: (e) { if (e.pointer == _pointerId) _release(); },
          child: Container(
            key: _key,
            width: s, height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle, color: _bg,
              boxShadow: [
                const BoxShadow(color: _ds, blurRadius: 10, offset: Offset(4, 4)),
                BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 9, offset: const Offset(-3, -3)),
              ],
            ),
            child: Center(
              child: Container(
                width: s * 0.78, height: s * 0.78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: _bg,
                  boxShadow: [
                    const BoxShadow(color: _ds, blurRadius: 7, offset: Offset(3, 3)),
                    BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 5, offset: const Offset(-2, -2)),
                  ],
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: _active ? Duration.zero : const Duration(milliseconds: 220),
                    curve: _active ? Curves.linear : const Cubic(0.34, 1.56, 0.64, 1),
                    width: s * 0.47, height: s * 0.47,
                    transform: Matrix4.translationValues(_dx * 0.65, _dy * 0.65, 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _active
                          ? const LinearGradient(begin: Alignment(-0.4, -0.8), end: Alignment(0.6, 0.8), colors: [_ac, Color(0xFF60C3FF)])
                          : null,
                      color: _active ? null : _bg,
                      boxShadow: _active
                          ? [BoxShadow(color: _ag, blurRadius: 18), const BoxShadow(color: _ds, blurRadius: 5, offset: Offset(2, 2))]
                          : [const BoxShadow(color: _ds, blurRadius: 10, offset: Offset(4, 4)), BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 9, offset: const Offset(-3, -3))],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(widget.label, style: const TextStyle(fontSize: 9, color: _muted, fontWeight: FontWeight.w700, letterSpacing: 0.09)),
      ],
    );
  }
}

class _DPadWidget extends StatefulWidget {
  final double size;
  final void Function(int bit, bool pressed) onButton;
  const _DPadWidget({required this.size, required this.onButton});

  @override
  State<_DPadWidget> createState() => _DPadWidgetState();
}

class _DPadWidgetState extends State<_DPadWidget> {
  final _held = <String>{};
  static const _bg = Color(0xFFD3E4F3);
  static const _ac = Color(0xFF1B8EF2);
  static const _ag = Color(0x4D1B8EF2);
  static const _ds = Color(0xFFA9BCCE);
  static const _ls = Color(0xE6FFFFFF);
  static const _muted = Color(0xFF6A8EAA);
  static const _dirMap = {'u': 4, 'd': 5, 'l': 6, 'r': 7};

  void _press(String d) {
    if (_held.add(d)) {
      widget.onButton(_dirMap[d]!, true);
    }
  }

  void _release(String d) {
    if (_held.remove(d)) {
      widget.onButton(_dirMap[d]!, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final a = s / 3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: s, height: s,
          child: Stack(
            children: [
              _dpadArm('u', '▲', a, 0, a, a, const BorderRadius.only(topLeft: Radius.circular(6), topRight: Radius.circular(6))),
              _dpadArm('d', '▼', a, a * 2, a, a, const BorderRadius.only(bottomLeft: Radius.circular(6), bottomRight: Radius.circular(6))),
              _dpadArm('l', '◀', 0, a, a, a, const BorderRadius.only(topLeft: Radius.circular(6), bottomLeft: Radius.circular(6))),
              _dpadArm('r', '▶', a * 2, a, a, a, const BorderRadius.only(topRight: Radius.circular(6), bottomRight: Radius.circular(6))),
              // 中心凹陷
              Positioned(left: a, top: a, width: a, height: a,
                child: Container(decoration: BoxDecoration(
                  color: _bg,
                  boxShadow: [
                    const BoxShadow(color: _ds, blurRadius: 4, offset: Offset(2, 2)),
                    BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 3, offset: const Offset(-1, -1)),
                  ],
                ))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text('D-PAD', style: TextStyle(fontSize: 9, color: _muted, fontWeight: FontWeight.w700, letterSpacing: 0.09)),
      ],
    );
  }

  Widget _dpadArm(String d, String icon, double x, double y, double w, double h, BorderRadius br) {
    final active = _held.contains(d);
    return Positioned(
      left: x, top: y, width: w, height: h,
      child: GestureDetector(
        onTapDown: (_) => _press(d),
        onTapUp: (_) => _release(d),
        onTapCancel: () => _release(d),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          decoration: BoxDecoration(
            color: active ? _ac : _bg,
            borderRadius: br,
            boxShadow: active
                ? [BoxShadow(color: _ag, blurRadius: 18, spreadRadius: 0), const BoxShadow(color: Color(0x2E000000), blurRadius: 5, offset: Offset(2, 2))]
                : [const BoxShadow(color: _ds, blurRadius: 10, offset: Offset(4, 4)), BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 9, offset: const Offset(-3, -3))],
          ),
          child: Center(child: Text(icon, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : _muted))),
        ),
      ),
    );
  }
}

class _FaceBtn extends StatefulWidget {
  final String label;
  final Color color;
  final double size;
  final ValueChanged<bool> onChanged;
  const _FaceBtn({required this.label, required this.color, required this.size, required this.onChanged});

  @override
  State<_FaceBtn> createState() => _FaceBtnState();
}

class _FaceBtnState extends State<_FaceBtn> {
  bool _active = false;
  static const _bg = Color(0xFFD3E4F3);
  static const _ds = Color(0xFFA9BCCE);
  static const _ls = Color(0xE6FFFFFF);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _active = true); widget.onChanged(true); },
      onTapUp: (_) { setState(() => _active = false); widget.onChanged(false); },
      onTapCancel: () { setState(() => _active = false); widget.onChanged(false); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size, height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active ? widget.color : _bg,
          border: _active ? null : Border.all(color: widget.color.withValues(alpha: 0.27), width: 2.5),
          boxShadow: _active
              ? [
                  BoxShadow(color: widget.color.withValues(alpha: 0.38), blurRadius: 20),
                  const BoxShadow(color: Color(0x38000000), blurRadius: 6, offset: Offset(2, 2)),
                  BoxShadow(color: _ls.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(-1, -1)),
                ]
              : [
                  const BoxShadow(color: _ds, blurRadius: 10, offset: Offset(4, 4)),
                  BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 9, offset: const Offset(-3, -3)),
                ],
        ),
        child: Center(
          child: Text(widget.label, style: TextStyle(
            fontSize: widget.size <= 46 ? 13 : 17,
            fontWeight: FontWeight.w900,
            color: _active ? Colors.white : widget.color,
          )),
        ),
      ),
    );
  }
}

class _FaceCluster extends StatelessWidget {
  final double btnSize;
  final Widget top, left, right, bottom;
  const _FaceCluster({required this.btnSize, required this.top, required this.left, required this.right, required this.bottom});

  @override
  Widget build(BuildContext context) {
    final gap = btnSize * 0.07;
    final w = btnSize * 2 + gap;
    return SizedBox(
      width: w, height: w,
      child: Stack(
        children: [
          Positioned(left: btnSize / 2 + gap / 2, top: 0, child: top),
          Positioned(left: 0, top: btnSize / 2 + gap / 2, child: left),
          Positioned(right: 0, top: btnSize / 2 + gap / 2, child: right),
          Positioned(left: btnSize / 2 + gap / 2, bottom: 0, child: bottom),
        ],
      ),
    );
  }
}

class _CenterBtn extends StatefulWidget {
  final String label;
  final double size;
  final ValueChanged<bool> onChanged;
  const _CenterBtn({required this.label, required this.size, required this.onChanged});

  @override
  State<_CenterBtn> createState() => _CenterBtnState();
}

class _CenterBtnState extends State<_CenterBtn> {
  bool _active = false;
  static const _bg = Color(0xFFD3E4F3);
  static const _ac = Color(0xFF1B8EF2);
  static const _ag = Color(0x4D1B8EF2);
  static const _ds = Color(0xFFA9BCCE);
  static const _ls = Color(0xE6FFFFFF);
  static const _muted = Color(0xFF6A8EAA);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _active = true); widget.onChanged(true); },
      onTapUp: (_) { setState(() => _active = false); widget.onChanged(false); },
      onTapCancel: () { setState(() => _active = false); widget.onChanged(false); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size, height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active ? _ac : _bg,
          boxShadow: _active
              ? [BoxShadow(color: _ag, blurRadius: 18), const BoxShadow(color: Color(0x2E000000), blurRadius: 5, offset: Offset(2, 2))]
              : [const BoxShadow(color: _ds, blurRadius: 10, offset: Offset(4, 4)), BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 9, offset: const Offset(-3, -3))],
        ),
        child: Center(
          child: Text(widget.label, style: TextStyle(
            fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: 0.03,
            color: _active ? Colors.white : _muted,
          ), textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _TouchpadBtn extends StatefulWidget {
  final double width, height;
  final ValueChanged<bool> onChanged;
  const _TouchpadBtn({required this.width, required this.height, required this.onChanged});

  @override
  State<_TouchpadBtn> createState() => _TouchpadBtnState();
}

class _TouchpadBtnState extends State<_TouchpadBtn> {
  bool _active = false;
  static const _bg = Color(0xFFD3E4F3);
  static const _ac = Color(0xFF1B8EF2);
  static const _ds = Color(0xFFA9BCCE);
  static const _ls = Color(0xE6FFFFFF);
  static const _muted = Color(0xFF6A8EAA);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _active = true); widget.onChanged(true); },
      onTapUp: (_) { setState(() => _active = false); widget.onChanged(false); },
      onTapCancel: () { setState(() => _active = false); widget.onChanged(false); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.width, height: widget.height,
        decoration: BoxDecoration(
          color: _bg, borderRadius: BorderRadius.circular(10),
          boxShadow: _active
              ? [
                  const BoxShadow(color: _ds, blurRadius: 8, offset: Offset(3, 3)),
                  BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 6, offset: const Offset(-2, -2)),
                ]
              : [
                  const BoxShadow(color: _ds, blurRadius: 10, offset: Offset(4, 4)),
                  BoxShadow(color: _ls.withValues(alpha: 0.9), blurRadius: 9, offset: const Offset(-3, -3)),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(width: 28, height: 2, decoration: BoxDecoration(color: _active ? _ac : _muted.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(1))),
            const SizedBox(height: 3),
            Text('TOUCH', style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w700, color: _active ? _ac : _muted, letterSpacing: 0.06)),
          ],
        ),
      ),
    );
  }
}
