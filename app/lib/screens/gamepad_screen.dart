import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/protocol.dart';
import '../services/ws_service.dart';
import '../utils/neu_tokens.dart';

/// SVG 图标辅助：加载 asset SVG 并染色
Widget _svgIcon(String asset, Color color, double size) {
  return SvgPicture.asset(
    asset,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

/// 拟态风格手柄主界面 (横屏)
class GamepadScreen extends StatefulWidget {
  final WsService wsService;
  final String mode; // "xbox" | "ps"
  const GamepadScreen({super.key, required this.wsService, required this.mode});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  double _lx = 0, _ly = 0, _rx = 0, _ry = 0;
  double _lt = 0, _rt = 0;
  int _buttons = 0;
  int _lastSentButtons = -1;
  double _lastLx = -999, _lastLy = -999, _lastRx = -999, _lastRy = -999;
  double _lastLt = -1, _lastRt = -1;

  Timer? _sendTimer;
  late final VoidCallback _wsListener;
  bool get _isXbox => widget.mode == 'xbox';

  static const int _bitA = 0, _bitB = 1, _bitX = 2, _bitY = 3;
  static const int _bitLB = 8, _bitRB = 9, _bitLS = 10, _bitRS = 11;
  static const int _bitBack = 12, _bitMenu = 13, _bitGuide = 14;

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
      if (!ws.isConnected && ws.state != ConnState.waitingAuth)
        _showDisconnect();
    };
    widget.wsService.addListener(_wsListener);
    _sendTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _sendState(),
    );
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
    if (_lx == _lastLx &&
        _ly == _lastLy &&
        _rx == _lastRx &&
        _ry == _lastRy &&
        _lt == _lastLt &&
        _rt == _lastRt &&
        _buttons == _lastSentButtons) {
      return;
    }
    widget.wsService.sendBinaryMsg(
      CGamepadState(_lx, _ly, _rx, _ry, _lt, _rt, _buttons),
    );
    _lastLx = _lx;
    _lastLy = _ly;
    _lastRx = _rx;
    _lastRy = _ry;
    _lastLt = _lt;
    _lastRt = _rt;
    _lastSentButtons = _buttons;
  }

  void _setButton(int bit, bool pressed) {
    setState(() {
      pressed ? _buttons |= (1 << bit) : _buttons &= ~(1 << bit);
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
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _exitGamepad() {
    widget.wsService.sendMessage(CGamepadDisconnect());
    Navigator.of(context).pop();
  }

  String _shoulderLabel(bool l) =>
      _isXbox ? (l ? 'LB' : 'RB') : (l ? 'L1' : 'R1');
  String _triggerLabel(bool l) =>
      _isXbox ? (l ? 'LT' : 'RT') : (l ? 'L2' : 'R2');
  String _stickLabel(bool l) => l ? 'L' : 'R'; // 摇杆下方显示
  String _stickPressLabel(bool l) =>
      _isXbox ? (l ? 'LS' : 'RS') : (l ? 'L3' : 'R3'); // 按下按钮

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: neuBg,
      body: Column(
        children: [
          // 扳机行
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: TriggerBar(
                    label: _triggerLabel(true),
                    align: 'left',
                    onChanged: (v) => setState(() => _lt = v),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TriggerBar(
                    label: _triggerLabel(false),
                    align: 'right',
                    onChanged: (v) => setState(() => _rt = v),
                  ),
                ),
              ],
            ),
          ),
          // 肩键行
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShoulderBtn(
                  label: _shoulderLabel(true),
                  onChanged: (v) => _setButton(_bitLB, v),
                ),
                ShoulderBtn(
                  label: _shoulderLabel(false),
                  onChanged: (v) => _setButton(_bitRB, v),
                ),
              ],
            ),
          ),
          // 主控制区
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: _isXbox ? _buildXbox() : _buildPS5(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Xbox 360 布局 ─────────────────────────────────────────────────────────
  // Left: LS(top) + DPad(bottom)
  // Center: Xbox Guide(top), VIEW(left-bottom), MENU(right-bottom)
  // Right: Face buttons(top) + RS(bottom)
  // LS/RS click buttons at bottom corners
  Widget _buildXbox() {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final jsSize = (h * 0.4).clamp(80.0, 125.0);
        final fbSize = (h * 0.135).clamp(43.0, 56.0);
        final dpSize = (h * 0.3).clamp(62.0, 96.0);
        final cnSize = (h * 0.09).clamp(28.0, 36.0);
        final hmSize = (h * 0.22).clamp(56.0, 74.0);

        final leftW = c.maxWidth * 0.32;
        final rightW = c.maxWidth * 0.32;

        return Stack(
          children: [
            // 左侧: LS over DPad
            Positioned(
              left: 0, top: 0, bottom: 0, width: leftW,
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: _JoystickWidget(
                        size: jsSize,
                        label: _stickLabel(true),
                        onChanged: (x, y) => setState(() { _lx = x; _ly = y; }),
                        onStickPress: (v) => _setButton(_bitLS, v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: DPadWidget(size: dpSize, onButton: _setButton, isXboxMode: true),
                    ),
                  ),
                ],
              ),
            ),
            // 中间: Guide(top), VIEW/MENU(下方10px)
            Positioned(
              left: leftW, right: rightW, top: 0, bottom: 0,
              child: Stack(
                children: [
                  Positioned(
                    top: 0, left: 0, right: 0,
                    height: hmSize,
                    child: Center(
                      child: HomeBtn(
                        size: hmSize,
                        icon: '⊞',
                        iconWidget: _svgIcon('assets/icons/Xbox.svg', const Color(0xFF43A047), hmSize * 0.7),
                        onDown: () => _setButton(_bitGuide, true),
                        onUp: () => _setButton(_bitGuide, false),
                        onLongPress: _exitGamepad,
                      ),
                    ),
                  ),
                  Positioned(
                    top: hmSize + 10, left: 0, right: 0,
                    height: cnSize,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        CenterBtn(
                          label: 'VIEW', size: cnSize,
                          iconWidgetBuilder: (active) => _svgIcon(
                            'assets/icons/Xbox VIEW_new.svg',
                            active ? Colors.white : neuMuted, cnSize * 0.55,
                          ),
                          onChanged: (v) => _setButton(_bitBack, v),
                        ),
                        CenterBtn(
                          label: 'MENU', size: cnSize,
                          iconWidgetBuilder: (active) => _svgIcon(
                            'assets/icons/Xbox and PS5 MENU.svg',
                            active ? Colors.white : neuMuted, cnSize * 0.55,
                          ),
                          onChanged: (v) => _setButton(_bitMenu, v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 右侧: Face buttons over RS
            Positioned(
              right: 0, top: 0, bottom: 0, width: rightW,
              child: Column(
                children: [
                  Expanded(child: Center(child: _xboxFace(fbSize))),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: _JoystickWidget(
                        size: jsSize,
                        label: _stickLabel(false),
                        onChanged: (x, y) => setState(() { _rx = x; _ry = y; }),
                        onStickPress: (v) => _setButton(_bitRS, v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // LS — 左摇杆右边缘 + 20px，与左摇杆水平对齐（上移5px）
            Positioned(
              left: leftW / 2 + jsSize / 2 + 20,
              top: h / 4 - 17,
              child: StickPressBtn(
                label: _stickPressLabel(true),
                onPressed: (v) => _setButton(_bitLS, v),
              ),
            ),
            // RS — 右摇杆左边缘 - 20px - btnW，与右摇杆水平对齐
            Positioned(
              right: rightW / 2 + jsSize / 2 + 20,
              top: h * 3 / 4 - 12,
              child: StickPressBtn(
                label: _stickPressLabel(false),
                onPressed: (v) => _setButton(_bitRS, v),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── PS5 布局 ──────────────────────────────────────────────────────────────
  // Left: DPad(top) + LS(bottom)
  // Center: PS Guide(top), Touchpad(below PS), CREATE/Options at sides
  // Right: Face buttons(top) + RS(bottom)
  // L3/R3 click buttons at bottom corners
  Widget _buildPS5() {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final jsSize = (h * 0.4).clamp(80.0, 125.0);
        final fbSize = (h * 0.135).clamp(43.0, 56.0);
        final dpSize = (h * 0.3).clamp(62.0, 96.0);
        final cnSize = (h * 0.085).clamp(24.0, 34.0);
        final hmSize = (h * 0.22).clamp(56.0, 74.0);
        final tpW = (h * 0.16).clamp(44.0, 58.0);
        final tpH = (h * 0.09).clamp(26.0, 36.0);

        final leftW = c.maxWidth * 0.32;
        final rightW = c.maxWidth * 0.32;

        return Stack(
          children: [
            // 左侧: DPad over LS
            Positioned(
              left: 0, top: 0, bottom: 0, width: leftW,
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: DPadWidget(size: dpSize, onButton: _setButton, isXboxMode: false),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: _JoystickWidget(
                        size: jsSize,
                        label: _stickLabel(true),
                        onChanged: (x, y) => setState(() { _lx = x; _ly = y; }),
                        onStickPress: (v) => _setButton(_bitLS, v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 中间: PS Guide + Touchpad
            Positioned(
              left: leftW, right: rightW, top: 0, bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  HomeBtn(
                    size: hmSize,
                    icon: 'PS',
                    iconWidget: _svgIcon('assets/icons/PS5.svg', const Color(0xFF1B8EF2), hmSize * 0.7),
                    onDown: () => _setButton(_bitGuide, true),
                    onUp: () => _setButton(_bitGuide, false),
                    onLongPress: _exitGamepad,
                  ),
                  const SizedBox(height: 8),
                  TouchpadBtn(
                    width: tpW, height: tpH,
                    onChanged: (v) => _setButton(_bitMenu, v),
                  ),
                ],
              ),
            ),
            // 右侧: Face buttons over RS
            Positioned(
              right: 0, top: 0, bottom: 0, width: rightW,
              child: Column(
                children: [
                  Expanded(child: Center(child: _ps5Face(fbSize))),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: _JoystickWidget(
                        size: jsSize,
                        label: _stickLabel(false),
                        onChanged: (x, y) => setState(() { _rx = x; _ry = y; }),
                        onStickPress: (v) => _setButton(_bitRS, v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // CREATE
            Positioned(
              left: leftW + 4, top: 8,
              child: CenterBtn(
                label: 'CREATE', size: cnSize,
                iconWidgetBuilder: (active) => _svgIcon(
                  'assets/icons/PS5 CREATE_new.svg',
                  active ? Colors.white : neuMuted, cnSize * 0.55,
                ),
                onChanged: (v) => _setButton(_bitBack, v),
              ),
            ),
            // OPTIONS
            Positioned(
              right: rightW + 4, top: 8,
              child: CenterBtn(
                label: 'OPTIONS', size: cnSize,
                iconWidgetBuilder: (active) => _svgIcon(
                  'assets/icons/Xbox and PS5 MENU.svg',
                  active ? Colors.white : neuMuted, cnSize * 0.55,
                ),
                onChanged: (v) => _setButton(_bitMenu, v),
              ),
            ),
            // L3 — 左摇杆右边缘 + 20px，与摇杆水平对齐
            Positioned(
              left: leftW / 2 + jsSize / 2 + 20,
              top: (h - 4) * 3 / 4 - 12,
              child: StickPressBtn(
                label: _stickPressLabel(true),
                onPressed: (v) => _setButton(_bitLS, v),
              ),
            ),
            // R3 — 右摇杆左边缘 - 20px - btnW，与摇杆水平对齐
            Positioned(
              right: rightW / 2 + jsSize / 2 + 20,
              top: (h - 4) * 3 / 4 - 12,
              child: StickPressBtn(
                label: _stickPressLabel(false),
                onPressed: (v) => _setButton(_bitRS, v),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─── Face clusters ────────────────────────────────────────────────────────
  Widget _xboxFace(double s) => FaceCluster(
    btnSize: s,
    top: FaceBtn(
      label: 'Y',
      color: const Color(0xFFF5A623),
      size: s,
      onChanged: (v) => _setButton(_bitY, v),
    ),
    left: FaceBtn(
      label: 'X',
      color: const Color(0xFF1B8EF2),
      size: s,
      onChanged: (v) => _setButton(_bitX, v),
    ),
    right: FaceBtn(
      label: 'B',
      color: const Color(0xFFE53935),
      size: s,
      onChanged: (v) => _setButton(_bitB, v),
    ),
    bottom: FaceBtn(
      label: 'A',
      color: const Color(0xFF43A047),
      size: s,
      onChanged: (v) => _setButton(_bitA, v),
    ),
  );

  Widget _ps5Face(double s) => FaceCluster(
    btnSize: s,
    top: FaceBtn(
      label: '△',
      color: const Color(0xFF5CC49A),
      size: s,
      onChanged: (v) => _setButton(_bitY, v),
    ),
    left: FaceBtn(
      label: '□',
      color: const Color(0xFFC46BC4),
      size: s,
      onChanged: (v) => _setButton(_bitX, v),
    ),
    right: FaceBtn(
      label: '○',
      color: const Color(0xFFE06060),
      size: s,
      onChanged: (v) => _setButton(_bitB, v),
    ),
    bottom: FaceBtn(
      label: '✕',
      color: const Color(0xFF6EA8DE),
      size: s,
      onChanged: (v) => _setButton(_bitA, v),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════════
//  Figma Make 拟态组件
//  Shadow map:
//    NEU_UP   = outer shadow at (4,4) dark + (-3,-3) light → RAISED/突起
//    NEU_DOWN = inset shadow at (3,3) dark + (-2,-2) light → INSET/凹陷
//    NEU_AC   = inset dark + outer glow → ACTIVE pressed
// ═══════════════════════════════════════════════════════════════════════════════════

/// Joystick:
///   Outer = NEU_UP (突起 raised)
///   Groove = NEU_DOWN (凹陷 inset) — `inset 3px 3px 7px DS, inset -2px -2px 5px LS`
///   Knob inactive = NEU_UP (突起 raised), active = glow + DS
class _JoystickWidget extends StatefulWidget {
  final double size;
  final String label;
  final void Function(double x, double y) onChanged;
  final ValueChanged<bool> onStickPress;
  const _JoystickWidget({
    required this.size,
    required this.label,
    required this.onChanged,
    required this.onStickPress,
  });

  @override
  State<_JoystickWidget> createState() => _JoystickWidgetState();
}

class _JoystickWidgetState extends State<_JoystickWidget> {
  double _dx = 0, _dy = 0;
  bool _active = false;
  int? _pid;
  final _key = GlobalKey();

  double get _maxR => widget.size * 0.27;

  void _update(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    var dx = global.dx - center.dx;
    var dy = global.dy - center.dy;
    final dist = Offset(dx, dy).distance;
    if (dist > _maxR) {
      dx = dx / dist * _maxR;
      dy = dy / dist * _maxR;
    }
    setState(() {
      _dx = dx;
      _dy = dy;
    });
    widget.onChanged(dx / _maxR, dy / _maxR);
  }

  void _release() {
    _pid = null;
    setState(() {
      _active = false;
      _dx = 0;
      _dy = 0;
    });
    widget.onChanged(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          key: _key,
          onPointerDown: (e) {
            _pid = e.pointer;
            setState(() => _active = true);
            _update(e.position);
          },
          onPointerMove: (e) {
            if (e.pointer == _pid) _update(e.position);
          },
          onPointerUp: (e) {
            if (e.pointer == _pid) _release();
          },
          onPointerCancel: (e) {
            if (e.pointer == _pid) _release();
          },
          child: Container(
            width: s,
            height: s,
            // 圆1: 外环 — 外阴影 突起 (柔和)
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: neuBg,
              boxShadow: [
                const BoxShadow(
                  color: neuDs,
                  blurRadius: 3,
                  offset: Offset(2, 2),
                ),
                BoxShadow(
                  color: neuLs.withValues(alpha: 0.5),
                  blurRadius: 1.5,
                  offset: const Offset(-2, -2),
                ),
              ],
            ),
            child: Center(
              child: Container(
                width: s * 0.78,
                height: s * 0.78,
                // 圆2: 凹槽 — 内阴影 凹陷 (柔和)
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: neuBg,
                  boxShadow: [
                    BoxShadow(
                      color: neuLs.withValues(alpha: 0.5),
                      blurRadius: 1,
                      blurStyle: BlurStyle.inner,
                      offset: const Offset(1, 1),
                    ),
                    const BoxShadow(
                      color: neuDs,
                      blurRadius: 2,
                      blurStyle: BlurStyle.inner,
                      offset: Offset(-1, -1),
                    ),
                  ],
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: _active
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: _active
                        ? Curves.linear
                        : const Cubic(0.34, 1.56, 0.64, 1),
                    width: s * 0.47,
                    height: s * 0.47,
                    transform: Matrix4.translationValues(
                      _dx * 0.65,
                      _dy * 0.65,
                      0,
                    ),
                    // 圆3: 旋钮 — 外阴影 突起 (柔和), 激活=渐变+微光
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _active
                          ? const LinearGradient(
                              begin: Alignment(-0.6, -0.8),
                              end: Alignment(0.8, 0.6),
                              colors: [neuAc, Color(0xFF60C3FF)],
                            )
                          : null,
                      color: _active ? null : neuBg,
                      boxShadow: _active
                          ? [
                              BoxShadow(color: neuAg, blurRadius: 6),
                              const BoxShadow(
                                color: neuDs,
                                blurRadius: 3,
                                offset: Offset(2, 2),
                              ),
                            ]
                          : [
                              const BoxShadow(
                                color: neuDs,
                                blurRadius: 3,
                                offset: Offset(2, 2),
                              ),
                              BoxShadow(
                                color: neuLs.withValues(alpha: 0.5),
                                blurRadius: 1.5,
                                offset: const Offset(-2, -2),
                              ),
                            ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 9,
            color: neuMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.09,
          ),
        ),
      ],
    );
  }
}

/// TriggerBar: NEU_UP (突起 raised) bar, gradient fill when active
class TriggerBar extends StatefulWidget {
  final String label;
  final String align;
  final ValueChanged<double> onChanged;
  const TriggerBar({
    super.key,
    required this.label,
    required this.align,
    required this.onChanged,
  });
  @override
  State<TriggerBar> createState() => _TriggerBarState();
}

class _TriggerBarState extends State<TriggerBar> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    final isLeft = widget.align == 'left';
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _active = true);
        widget.onChanged(1.0);
      },
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onChanged(0.0);
      },
      onTapCancel: () {
        setState(() => _active = false);
        widget.onChanged(0.0);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: 42,
        decoration: BoxDecoration(
          color: neuBg,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isLeft ? 10 : 4),
            bottomLeft: Radius.circular(isLeft ? 10 : 4),
            topRight: Radius.circular(isLeft ? 4 : 10),
            bottomRight: Radius.circular(isLeft ? 4 : 10),
          ),
          boxShadow: _active
              ? [
                  BoxShadow(color: neuDs, blurRadius: 4, offset: Offset(3, 3)),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.5),
                    blurRadius: 2,
                    offset: Offset(-2, -2),
                  ),
                ]
              : [
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(4, 4)),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.5),
                    blurRadius: 1.5,
                    offset: Offset(-3, -3),
                  ),
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
                      topLeft: Radius.circular(isLeft ? 10 : 4),
                      bottomLeft: Radius.circular(isLeft ? 10 : 4),
                      topRight: Radius.circular(isLeft ? 4 : 10),
                      bottomRight: Radius.circular(isLeft ? 4 : 10),
                    ),
                    gradient: isLeft
                        ? const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0xB31B8EF2), Color(0x001B8EF2)],
                          )
                        : const LinearGradient(
                            begin: Alignment.centerRight,
                            end: Alignment.centerLeft,
                            colors: [Color(0xB31B8EF2), Color(0x001B8EF2)],
                          ),
                  ),
                ),
              ),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _active ? neuAc : neuMuted,
                letterSpacing: 0.08,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ShoulderBtn: NEU_UP (突起 raised), fills accent + NEU_AC when active
class ShoulderBtn extends StatefulWidget {
  final String label;
  final ValueChanged<bool> onChanged;
  const ShoulderBtn({super.key, required this.label, required this.onChanged});
  @override
  State<ShoulderBtn> createState() => _ShoulderBtnState();
}

class _ShoulderBtnState extends State<ShoulderBtn> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _active = true);
        widget.onChanged(true);
      },
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      onTapCancel: () {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 76,
        height: 30,
        decoration: BoxDecoration(
          color: _active ? neuAc : neuBg,
          borderRadius: BorderRadius.circular(8),
          boxShadow: _active
              ? [
                  BoxShadow(color: neuAg, blurRadius: 6),
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(2, 2)),
                ]
              : [
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(4, 4)),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.5),
                    blurRadius: 1.5,
                    offset: Offset(-3, -3),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _active ? Colors.white : neuMuted,
              letterSpacing: 0.07,
            ),
          ),
        ),
      ),
    );
  }
}

/// DPad: Xbox = circular outer + cross arms (neumorphic); PS5 = cross arms + center
class DPadWidget extends StatefulWidget {
  final double size;
  final void Function(int bit, bool pressed) onButton;
  final bool isXboxMode;
  const DPadWidget({
    super.key,
    required this.size,
    required this.onButton,
    this.isXboxMode = false,
  });
  @override
  State<DPadWidget> createState() => _DPadWidgetState();
}

class _DPadWidgetState extends State<DPadWidget> {
  final _held = <String>{};
  static const _dirBit = {'u': 4, 'd': 5, 'l': 6, 'r': 7};

  void _press(String d) {
    if (_held.add(d)) widget.onButton(_dirBit[d]!, true);
  }

  void _release(String d) {
    if (_held.remove(d)) widget.onButton(_dirBit[d]!, false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final a = s / 3;
    bool active(String d) => _held.contains(d);

    // 4 arm definitions: (dir, x, y, w, h, borderRadius)
    final arms = <(String, double, double, double, double, BorderRadius)>[
      ('u', a, 0, a, a, widget.isXboxMode
          ? const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8))
          : const BorderRadius.all(Radius.circular(6))),
      ('d', a, a * 2, a, a, widget.isXboxMode
          ? const BorderRadius.only(bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8))
          : const BorderRadius.all(Radius.circular(6))),
      ('l', 0, a, a, a, widget.isXboxMode
          ? const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8))
          : const BorderRadius.all(Radius.circular(6))),
      ('r', a * 2, a, a, a, widget.isXboxMode
          ? const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8))
          : const BorderRadius.all(Radius.circular(6))),
    ];

    final centerSize = a * 0.72;

    final cross = Stack(
      children: [
        // 4 arms
        for (final (d, x, y, w, h, br) in arms)
          Positioned(
            left: x,
            top: y,
            width: w,
            height: h,
            child: GestureDetector(
              onTapDown: (_) => _press(d),
              onTapUp: (_) => _release(d),
              onTapCancel: () => _release(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                decoration: BoxDecoration(
                  color: active(d) ? neuAc : neuBg,
                  borderRadius: br,
                  boxShadow: active(d)
                      ? [
                          BoxShadow(color: neuAg, blurRadius: 6),
                          BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(2, 2)),
                        ]
                      : [
                          BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(4, 4)),
                          BoxShadow(
                            color: neuLs.withValues(alpha: 0.5),
                            blurRadius: 1.5,
                            offset: Offset(-3, -3),
                          ),
                        ],
                ),
              ),
            ),
          ),
        // Center (凹陷 inset)
        Positioned(
          left: a + (a - centerSize) / 2,
          top: a + (a - centerSize) / 2,
          width: centerSize,
          height: centerSize,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: neuBg,
              boxShadow: [
                BoxShadow(
                  color: neuLs.withValues(alpha: 0.9),
                  blurRadius: 1,
                  blurStyle: BlurStyle.inner,
                  offset: const Offset(1, 1),
                ),
                const BoxShadow(
                  color: neuDs,
                  blurRadius: 2,
                  blurStyle: BlurStyle.inner,
                  offset: Offset(-1, -1),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: s,
          height: s,
          child: widget.isXboxMode
              ? Container(
                  // Xbox: circular outer track with inset neumorphic shadow
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: neuBg,
                    boxShadow: [
                      BoxShadow(
                        color: neuLs.withValues(alpha: 0.9),
                        blurRadius: 3,
                        blurStyle: BlurStyle.inner,
                        offset: const Offset(1, 1),
                      ),
                      const BoxShadow(
                        color: neuDs,
                        blurRadius: 6,
                        blurStyle: BlurStyle.inner,
                        offset: Offset(-2, -2),
                      ),
                    ],
                  ),
                  child: ClipOval(child: cross),
                )
              : cross, // PS5: no outer circle
        ),
        const SizedBox(height: 6),
        const Text(
          'D-PAD',
          style: TextStyle(
            fontSize: 9,
            color: neuMuted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.09,
          ),
        ),
      ],
    );
  }
}

/// FaceBtn: NEU_UP (突起 raised) when inactive, filled + glow when active
class FaceBtn extends StatefulWidget {
  final String label;
  final Color color;
  final double size;
  final ValueChanged<bool> onChanged;
  const FaceBtn({
    super.key,
    required this.label,
    required this.color,
    required this.size,
    required this.onChanged,
  });
  @override
  State<FaceBtn> createState() => _FaceBtnState();
}

class _FaceBtnState extends State<FaceBtn> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _active = true);
        widget.onChanged(true);
      },
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      onTapCancel: () {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active ? widget.color : neuBg,
          border: _active
              ? null
              : Border.all(
                  color: widget.color.withValues(alpha: 0.27),
                  width: 2.5,
                ),
          // inactive: NEU_UP (突起), active: colored glow + inset (凹陷)
          // inactive: NEU_UP (突起), active: colored glow + inset (凹陷)
          boxShadow: _active
              ? [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.3),
                    blurRadius: 6,
                  ),
                  BoxShadow(
                    color: Color(0x38000000),
                    blurRadius: 3,
                    blurStyle: BlurStyle.inner,
                    offset: Offset(1, 1),
                  ),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.15),
                    blurRadius: 1.5,
                    blurStyle: BlurStyle.inner,
                    offset: Offset(-1, -1),
                  ),
                ]
              : [
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(4, 4)),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.5),
                    blurRadius: 1.5,
                    offset: Offset(-3, -3),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.size <= 46 ? 13 : 17,
              fontWeight: FontWeight.w900,
              color: _active ? Colors.white : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Face cluster: diamond layout with small gap between buttons (not stacked)
class FaceCluster extends StatelessWidget {
  final double btnSize;
  final Widget top, left, right, bottom;
  const FaceCluster({
    super.key,
    required this.btnSize,
    required this.top,
    required this.left,
    required this.right,
    required this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    // Diamond layout: visible gap between all 4 buttons (not stacked)
    const gap = 30.0;
    final w = btnSize * 2 + gap;
    return SizedBox(
      width: w,
      height: w,
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

/// HomeBtn: large glowing gradient circle, NEU_UP (突起), long press 2s to exit
class HomeBtn extends StatefulWidget {
  final double size;
  final String icon;
  final Widget? iconWidget;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final VoidCallback onLongPress;
  const HomeBtn({
    super.key,
    required this.size,
    required this.icon,
    this.iconWidget,
    required this.onDown,
    required this.onUp,
    required this.onLongPress,
  });
  @override
  State<HomeBtn> createState() => _HomeBtnState();
}

class _HomeBtnState extends State<HomeBtn> {
  bool _active = false;
  Timer? _lpTimer;
  @override
  void dispose() {
    _lpTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _active = true);
        widget.onDown();
        _lpTimer?.cancel();
        _lpTimer = Timer(const Duration(seconds: 2), widget.onLongPress);
      },
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onUp();
        _lpTimer?.cancel();
      },
      onTapCancel: () {
        setState(() => _active = false);
        widget.onUp();
        _lpTimer?.cancel();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active ? neuDs.withValues(alpha: 0.35) : neuBg,
          boxShadow: _active
              ? [
                  BoxShadow(
                    color: neuDs,
                    blurRadius: 4,
                    blurStyle: BlurStyle.inner,
                    offset: const Offset(2, 2),
                  ),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.6),
                    blurRadius: 3,
                    blurStyle: BlurStyle.inner,
                    offset: const Offset(-1, -1),
                  ),
                ]
              : [
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(4, 4)),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.5),
                    blurRadius: 1.5,
                    offset: Offset(-3, -3),
                  ),
                ],
        ),
        child: Center(
          child: widget.iconWidget ??
            Text(
              widget.icon,
              style: const TextStyle(
                color: neuMuted,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
        ),
      ),
    );
  }
}

/// CenterBtn: small NEU_UP (突起 raised) circle
class CenterBtn extends StatefulWidget {
  final String label;
  final double size;
  final Widget Function(bool active)? iconWidgetBuilder;
  final ValueChanged<bool> onChanged;
  const CenterBtn({
    super.key,
    required this.label,
    required this.size,
    this.iconWidgetBuilder,
    required this.onChanged,
  });
  @override
  State<CenterBtn> createState() => _CenterBtnState();
}

class _CenterBtnState extends State<CenterBtn> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _active = true);
        widget.onChanged(true);
      },
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      onTapCancel: () {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _active ? neuAc : neuBg,
          boxShadow: _active
              ? [
                  BoxShadow(color: neuAg, blurRadius: 6),
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(2, 2)),
                ]
              : [
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(4, 4)),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.5),
                    blurRadius: 1.5,
                    offset: Offset(-3, -3),
                  ),
                ],
        ),
        child: Center(
          child: widget.iconWidgetBuilder != null
            ? widget.iconWidgetBuilder!(_active)
            : Text(
                widget.label,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.03,
                  color: _active ? Colors.white : neuMuted,
                ),
                textAlign: TextAlign.center,
              ),
        ),
      ),
    );
  }
}

/// TouchpadBtn (PS5): NEU_UP (突起 raised) rect
class TouchpadBtn extends StatefulWidget {
  final double width, height;
  final ValueChanged<bool> onChanged;
  const TouchpadBtn({
    super.key,
    required this.width,
    required this.height,
    required this.onChanged,
  });
  @override
  State<TouchpadBtn> createState() => _TouchpadBtnState();
}

class _TouchpadBtnState extends State<TouchpadBtn> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _active = true);
        widget.onChanged(true);
      },
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      onTapCancel: () {
        setState(() => _active = false);
        widget.onChanged(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: neuBg,
          borderRadius: BorderRadius.circular(10),
          boxShadow: _active
              ? const [
                  BoxShadow(
                    color: neuDs,
                    blurRadius: 8,
                    blurStyle: BlurStyle.inner,
                    offset: Offset(3, 3),
                  ),
                  BoxShadow(
                    color: neuLs,
                    blurRadius: 6,
                    blurStyle: BlurStyle.inner,
                    offset: Offset(-2, -2),
                  ),
                ]
              : [
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(4, 4)),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.5),
                    blurRadius: 1.5,
                    offset: Offset(-3, -3),
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 2,
              decoration: BoxDecoration(
                color: _active ? neuAc : neuMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'TOUCH',
              style: TextStyle(
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                color: _active ? neuAc : neuMuted,
                letterSpacing: 0.06,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// StickPressBtn: small button for LS/RS click, at bottom corners
class StickPressBtn extends StatefulWidget {
  final String label;
  final ValueChanged<bool> onPressed;
  const StickPressBtn({
    super.key,
    required this.label,
    required this.onPressed,
  });
  @override
  State<StickPressBtn> createState() => _StickPressBtnState();
}

class _StickPressBtnState extends State<StickPressBtn> {
  bool _active = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _active = true);
        widget.onPressed(true);
      },
      onTapUp: (_) {
        setState(() => _active = false);
        widget.onPressed(false);
      },
      onTapCancel: () {
        setState(() => _active = false);
        widget.onPressed(false);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 40,
        height: 24,
        decoration: BoxDecoration(
          color: _active ? neuAc : neuBg,
          borderRadius: BorderRadius.circular(6),
          boxShadow: _active
              ? [
                  BoxShadow(color: neuAg, blurRadius: 6),
                  BoxShadow(color: neuDs, blurRadius: 2, offset: Offset(1, 1)),
                ]
              : [
                  BoxShadow(color: neuDs, blurRadius: 3, offset: Offset(2, 2)),
                  BoxShadow(
                    color: neuLs.withValues(alpha: 0.5),
                    blurRadius: 1.5,
                    offset: Offset(-2, -2),
                  ),
                ],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: _active ? Colors.white : neuMuted,
              letterSpacing: 0.05,
            ),
          ),
        ),
      ),
    );
  }
}
