import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gamepad_layout.dart';
import '../models/protocol.dart';
import '../services/ws_service.dart';
import '../widgets/gamepad_widgets.dart';

/// 自定义布局运行界面（横屏）
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

  // 按钮位映射
  static const _buttonBits = {
    'a': 0, 'b': 1, 'x': 2, 'y': 3,
    'up': 4, 'down': 5, 'left': 6, 'right': 7,
    'lb': 8, 'rb': 9, 'lt': 8, 'rt': 9,
    'ls': 10, 'rs': 11,
    'back': 12, 'menu': 13, 'guide': 14,
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
        _buttons == _lastSentButtons) return;
    widget.wsService.sendMessage(
      CGamepadState(_lx, _ly, _rx, _ry, 0, 0, _buttons),
    );
    _lastLx = _lx; _lastLy = _ly;
    _lastRx = _rx; _lastRy = _ry;
    _lastSentButtons = _buttons;
  }

  void _setButton(String? id, bool pressed) {
    if (id == null) return;
    final bit = _buttonBits[id];
    if (bit == null) return;
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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final topBarH = 34.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0f1a2e),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(topBarH),
            Expanded(
              child: Stack(
                children: [
                  for (int i = 0; i < widget.layout.elements.length; i++)
                    _buildElement(i, screenW, screenH - topBarH),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(double h) {
    return Container(
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF162240),
        border: Border(bottom: BorderSide(color: Color(0xFF2a4a70), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              widget.wsService.sendMessage(CGamepadDisconnect());
              Navigator.of(context).pop();
            },
            child: const Icon(Icons.arrow_back, color: Color(0xFF8ab4e0), size: 18),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.tune, color: Color(0xFF4a9eff), size: 16),
          const SizedBox(width: 5),
          Text(
            widget.layout.name,
            style: const TextStyle(color: Color(0xFF8ab4e0), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF34a853), shape: BoxShape.circle)),
          const SizedBox(width: 5),
          const Text('已连接', style: TextStyle(color: Color(0xFF6e8aa8), fontSize: 12)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              widget.wsService.sendMessage(CGamepadDisconnect());
              widget.wsService.disconnect();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('断开', style: TextStyle(color: Color(0xFFe53935), fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildElement(int index, double screenW, double screenH) {
    final el = widget.layout.elements[index];
    final size = el.size * screenH;
    final centerX = el.x * screenW;
    final centerY = el.y * screenH;

    if (el.type == 'joystick') {
      return Positioned(
        left: centerX - size / 2,
        top: centerY - size / 2,
        child: JoystickWidget(
          size: size,
          label: el.stickSide == 'left' ? 'L' : 'R',
          onChange: (x, y) {
            setState(() {
              if (el.stickSide == 'left') {
                _lx = x; _ly = y;
              } else {
                _rx = x; _ry = y;
              }
            });
          },
        ),
      );
    }

    if (el.type == 'touchpad') {
      final w = size * 1.5;
      final h = size;
      return Positioned(
        left: centerX - w / 2,
        top: centerY - h / 2,
        child: _TouchpadStickWidget(
          width: w,
          height: h,
          sensitivity: el.sensitivity ?? 1.0,
          onChange: (x, y) {
            setState(() {
              if (el.mapTo == 'left') {
                _lx = x; _ly = y;
              } else {
                _rx = x; _ry = y;
              }
            });
          },
        ),
      );
    }

    // button
    return Positioned(
      left: centerX - size / 2,
      top: centerY - size / 2,
      child: GamepadButton(
        label: el.label ?? el.buttonId ?? '?',
        size: size,
        color: const Color(0xFF8ab4e0),
        bgColor: const Color(0xFF2a3f5f),
        onPressed: (p) => _setButton(el.buttonId, p),
      ),
    );
  }
}

/// 触控板 → 摇杆映射 Widget
class _TouchpadStickWidget extends StatefulWidget {
  final double width, height;
  final double sensitivity;
  final void Function(double x, double y) onChange;

  const _TouchpadStickWidget({
    required this.width,
    required this.height,
    required this.sensitivity,
    required this.onChange,
  });

  @override
  State<_TouchpadStickWidget> createState() => _TouchpadStickWidgetState();
}

class _TouchpadStickWidgetState extends State<_TouchpadStickWidget> {
  int? _pointerId;

  void _handlePointerDown(PointerDownEvent e) {
    _pointerId = e.pointer;
    _updatePosition(e.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent e) {
    if (e.pointer == _pointerId) _updatePosition(e.localPosition);
  }

  void _handlePointerUp(PointerUpEvent e) {
    if (e.pointer == _pointerId) {
      _pointerId = null;
      widget.onChange(0, 0);
    }
  }

  void _handlePointerCancel(PointerCancelEvent e) {
    if (e.pointer == _pointerId) {
      _pointerId = null;
      widget.onChange(0, 0);
    }
  }

  void _updatePosition(Offset local) {
    final cx = widget.width / 2;
    final cy = widget.height / 2;
    final nx = ((local.dx - cx) / cx * widget.sensitivity).clamp(-1.0, 1.0);
    final ny = ((local.dy - cy) / cy * widget.sensitivity).clamp(-1.0, 1.0);
    widget.onChange(nx, ny);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: const Color(0xFF1e3352),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF2a4a70), width: 1),
        ),
        child: const Center(
          child: Icon(Icons.touch_app, color: Color(0xFF3a5a80), size: 24),
        ),
      ),
    );
  }
}
