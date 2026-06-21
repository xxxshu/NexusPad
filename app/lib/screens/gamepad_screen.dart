import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';
import '../services/ws_service.dart';
import '../widgets/gamepad_widgets.dart';

/// 手柄主界面 (横屏)
class GamepadScreen extends StatefulWidget {
  final WsService wsService;
  final String mode; // "xbox" | "ps"
  const GamepadScreen({super.key, required this.wsService, required this.mode});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  // 摇杆状态
  double _lx = 0, _ly = 0, _rx = 0, _ry = 0;
  // 扳机状态
  double _lt = 0, _rt = 0;
  // 按钮位掩码
  int _buttons = 0;
  // 上一次发送的状态 (用于变化检测)
  int _lastSentButtons = -1;
  double _lastLx = -999, _lastLy = -999, _lastRx = -999, _lastRy = -999;
  double _lastLt = -1, _lastRt = -1;

  Timer? _sendTimer;
  late final VoidCallback _wsListener;

  bool get _isXbox => widget.mode == 'xbox';

  // 按钮位定义
  static const int _bitA = 0, _bitB = 1, _bitX = 2, _bitY = 3;
  // 4-7 = DPad (handled by DpadWidget internally)
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

    // 断连监听
    _wsListener = () {
      if (!mounted) return;
      final ws = widget.wsService;
      if (!ws.isConnected && ws.state != ConnState.waitingAuth) {
        _showDisconnect();
      }
    };
    widget.wsService.addListener(_wsListener);

    // 60fps 发送循环
    _sendTimer = Timer.periodic(const Duration(milliseconds: 16), (_) => _sendState());
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    widget.wsService.removeListener(_wsListener);
    // 销毁虚拟手柄
    widget.wsService.sendMessage(CGamepadDisconnect());
    // 恢复竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _sendState() {
    // 只在状态变化时发送
    if (_lx == _lastLx && _ly == _lastLy &&
        _rx == _lastRx && _ry == _lastRy &&
        _lt == _lastLt && _rt == _lastRt &&
        _buttons == _lastSentButtons) return;

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

  // ─── 按钮标签和颜色 ───

  String _faceBtnLabel(int bit) {
    if (_isXbox) {
      return switch (bit) { _bitA => 'A', _bitB => 'B', _bitX => 'X', _bitY => 'Y', _ => '' };
    } else {
      return switch (bit) { _bitA => '×', _bitB => '○', _bitX => '□', _bitY => '△', _ => '' };
    }
  }

  Color _faceBtnColor(int bit) {
    return switch (bit) {
      _bitA => _isXbox ? const Color(0xFF2d8f2d) : const Color(0xFF2d8f2d),
      _bitB => _isXbox ? const Color(0xFFc43030) : const Color(0xFFc43030),
      _bitX => _isXbox ? const Color(0xFF2563c4) : const Color(0xFFd468a8),
      _bitY => _isXbox ? const Color(0xFFc4a025) : const Color(0xFF2563c4),
      _ => Colors.white,
    };
  }

  String _shoulderLabel(bool isLeft) {
    if (_isXbox) return isLeft ? 'LB' : 'RB';
    return isLeft ? 'L1' : 'R1';
  }

  String _triggerLabel(bool isLeft) {
    if (_isXbox) return isLeft ? 'LT' : 'RT';
    return isLeft ? 'L2' : 'R2';
  }

  String _stickLabel(bool isLeft) {
    if (_isXbox) return isLeft ? 'LS' : 'RS';
    return isLeft ? 'L3' : 'R3';
  }

  // ─── 构建 UI ───

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final topBarH = 34.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0f1a2e),
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏
            _buildTopBar(topBarH),
            // 手柄区域
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: _buildGamepad(screenH - topBarH),
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
          const Icon(Icons.gamepad, color: Color(0xFF4a9eff), size: 16),
          const SizedBox(width: 5),
          Text(
            _isXbox ? 'Xbox 360' : 'PS5',
            style: const TextStyle(
              color: Color(0xFF8ab4e0),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF34a853),
              shape: BoxShape.circle,
            ),
          ),
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

  Widget _buildGamepad(double availableH) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final stickSize = h * 0.52;
        final btnSize = h * 0.18;
        final dpadSize = h * 0.46;
        final shoulderH = h * 0.16;
        final triggerH = h * 0.18;

        return Stack(
          children: [
            // ── 扳机键 (顶部) ──
            Positioned(
              left: 20, top: 0,
              child: GamepadButton(
                label: _triggerLabel(true),
                size: triggerH,
                color: const Color(0xFF8ab4e0),
                bgColor: const Color(0xFF1a2d4a),
                onPressed: (p) => _setButton(_isXbox ? 8 : 8, p), // LT/L2 → 按钮位 8 (临时)
              ),
            ),
            Positioned(
              right: 20, top: 0,
              child: GamepadButton(
                label: _triggerLabel(false),
                size: triggerH,
                color: const Color(0xFF8ab4e0),
                bgColor: const Color(0xFF1a2d4a),
                onPressed: (p) => _setButton(_isXbox ? 9 : 9, p), // RT/R2 → 按钮位 9 (临时)
              ),
            ),

            // ── 肩键 (扳机下方) ──
            Positioned(
              left: 60, top: triggerH * 0.6,
              child: GamepadButton(
                label: _shoulderLabel(true),
                size: shoulderH,
                color: const Color(0xFF8ab4e0),
                bgColor: const Color(0xFF1a2d4a),
                onPressed: (p) => _setButton(_bitLB, p),
              ),
            ),
            Positioned(
              right: 60, top: triggerH * 0.6,
              child: GamepadButton(
                label: _shoulderLabel(false),
                size: shoulderH,
                color: const Color(0xFF8ab4e0),
                bgColor: const Color(0xFF1a2d4a),
                onPressed: (p) => _setButton(_bitRB, p),
              ),
            ),

            // ── 左摇杆 ──
            Positioned(
              left: 16,
              bottom: 8,
              child: Column(
                children: [
                  JoystickWidget(
                    size: stickSize,
                    label: 'L',
                    onChange: (x, y) {
                      setState(() { _lx = x; _ly = y; });
                    },
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTapDown: (_) => _setButton(_bitLS, true),
                    onTapUp: (_) => _setButton(_bitLS, false),
                    onTapCancel: () => _setButton(_bitLS, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a2d4a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2a4a70), width: 1),
                      ),
                      child: Text(
                        _stickLabel(true),
                        style: const TextStyle(color: Color(0xFF6e8aa8), fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 右摇杆 ──
            Positioned(
              right: 16,
              bottom: 8,
              child: Column(
                children: [
                  JoystickWidget(
                    size: stickSize,
                    label: 'R',
                    onChange: (x, y) {
                      setState(() { _rx = x; _ry = y; });
                    },
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTapDown: (_) => _setButton(_bitRS, true),
                    onTapUp: (_) => _setButton(_bitRS, false),
                    onTapCancel: () => _setButton(_bitRS, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a2d4a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2a4a70), width: 1),
                      ),
                      child: Text(
                        _stickLabel(false),
                        style: const TextStyle(color: Color(0xFF6e8aa8), fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 十字键 (左摇杆右边) ──
            Positioned(
              left: stickSize + 40,
              bottom: (h - dpadSize) / 2 - 4,
              child: DpadWidget(
                size: dpadSize,
                onButton: _setButton,
              ),
            ),

            // ── 中间功能键 ──
            Positioned(
              left: w / 2 - 80,
              top: h * 0.25,
              child: _buildCenterButtons(),
            ),

            // ── 面部按钮 (右侧) ──
            Positioned(
              right: stickSize + 40,
              bottom: (h - btnSize * 3.5) / 2,
              child: _buildFaceButtons(btnSize),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCenterButtons() {
    if (_isXbox) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Map (叠加方块图标)
          _smallBtn(Icons.crop_square, _bitBack),
          const SizedBox(width: 12),
          // Guide (大 X)
          _guideBtn(),
          const SizedBox(width: 12),
          // Menu (三条横杠)
          _smallBtn(Icons.menu, _bitMenu),
        ],
      );
    } else {
      // PS5
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Share
          _smallBtn(Icons.share, _bitBack),
          const SizedBox(width: 12),
          // PS
          _guideBtn(),
          const SizedBox(width: 12),
          // Option
          _smallBtn(Icons.menu, _bitMenu),
        ],
      );
    }
  }

  Widget _smallBtn(IconData icon, int bit) {
    return GamepadButton(
      size: 36,
      color: const Color(0xFF6e8aa8),
      bgColor: const Color(0xFF162840),
      onPressed: (p) => _setButton(bit, p),
      child: Icon(icon, color: const Color(0xFF6e8aa8), size: 16),
    );
  }

  Widget _guideBtn() {
    return GestureDetector(
      onTapDown: (_) => _setButton(_bitGuide, true),
      onTapUp: (_) => _setButton(_bitGuide, false),
      onTapCancel: () => _setButton(_bitGuide, false),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF162840),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF2a4a70), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: _isXbox
              ? const Text('X', style: TextStyle(color: Color(0xFF4a9eff), fontSize: 18, fontWeight: FontWeight.w800))
              : const Text('PS', style: TextStyle(color: Color(0xFF4a9eff), fontSize: 12, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  Widget _buildFaceButtons(double btnSize) {
    // ABXY / ×○□△ 布局 (菱形)
    final spacing = btnSize * 0.15;
    return SizedBox(
      width: btnSize * 2 + spacing,
      height: btnSize * 2 + spacing,
      child: Stack(
        children: [
          // Y / △ (上)
          Positioned(
            left: btnSize / 2 + spacing / 2,
            top: 0,
            child: GamepadButton(
              label: _faceBtnLabel(_bitY),
              size: btnSize,
              color: _faceBtnColor(_bitY),
              onPressed: (p) => _setButton(_bitY, p),
            ),
          ),
          // X / □ (左)
          Positioned(
            left: 0,
            top: btnSize / 2 + spacing / 2,
            child: GamepadButton(
              label: _faceBtnLabel(_bitX),
              size: btnSize,
              color: _faceBtnColor(_bitX),
              onPressed: (p) => _setButton(_bitX, p),
            ),
          ),
          // B / ○ (右)
          Positioned(
            right: 0,
            top: btnSize / 2 + spacing / 2,
            child: GamepadButton(
              label: _faceBtnLabel(_bitB),
              size: btnSize,
              color: _faceBtnColor(_bitB),
              onPressed: (p) => _setButton(_bitB, p),
            ),
          ),
          // A / × (下)
          Positioned(
            left: btnSize / 2 + spacing / 2,
            bottom: 0,
            child: GamepadButton(
              label: _faceBtnLabel(_bitA),
              size: btnSize,
              color: _faceBtnColor(_bitA),
              onPressed: (p) => _setButton(_bitA, p),
            ),
          ),
        ],
      ),
    );
  }
}
