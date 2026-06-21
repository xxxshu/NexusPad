import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/protocol.dart';
import '../services/ws_service.dart';
import '../utils/gesture_engine.dart';
import '../utils/haptic.dart';

class TouchpadScreen extends StatefulWidget {
  final WsService wsService;
  const TouchpadScreen({super.key, required this.wsService});

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen>
    with SingleTickerProviderStateMixin {
  late final GestureEngine _engine;
  final _touchpadKey = GlobalKey(); // 用于坐标转换
  bool _ready = false; // 等横屏生效后再渲染
  bool _fkVisible = true;
  bool _oskVisible = false;
  int _shiftState = 0;
  bool _symLayer = false;
  GestureMode _gestureMode = GestureMode.idle;
  final Map<String, bool> _modState = {'ctrl': false, 'shift': false, 'alt': false};

  // 涟漪
  final List<_RippleData> _ripples = [];
  // 手指位置（用于涟漪定位）
  double _lastTouchX = 0, _lastTouchY = 0;

  // 退格长按
  Timer? _bsRepeatStart;
  Timer? _bsRepeatInterval;

  // 按键阴影（网页版所有键统一）
  // 网页版 CSS: box-shadow: 0 1.5px 0 #9dbedd
  static const _keyShadow = [
    BoxShadow(color: Color(0xFF9dbedd), blurRadius: 0, offset: Offset(0, 1.5))
  ];
  // 网页版 modifier key: box-shadow: 0 1.5px 0 #90bad6
  static const _modKeyShadow = [
    BoxShadow(color: Color(0xFF90bad6), blurRadius: 0, offset: Offset(0, 1.5))
  ];

  @override
  void initState() {
    super.initState();
    // 先切横屏，等生效后再渲染 UI（避免闪烁）
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _ready = true);
    });

    Haptic.init();
    _loadSensitivity();
    _engine = GestureEngine(GestureCallbacks(
      onMove: (dx, dy) => widget.wsService.sendMessage(CMove(dx, dy)),
      onClick: () {
        widget.wsService.sendMessage(CClick(1));
      },
      onDblClick: () => widget.wsService.sendMessage(CDblClick()),
      onRightClick: () => widget.wsService.sendMessage(CClick(3)),
      onMouseDown: () => widget.wsService.sendMessage(CMouseDown(1)),
      onMouseUp: () => widget.wsService.sendMessage(CMouseUp(1)),
      onScroll: (dx, dy) =>
          widget.wsService.sendMessage(CScroll(dx.toDouble(), dy.toDouble())),
      onPinch: (m) => widget.wsService.sendMessage(CPinchZoom(m)),
      onModeChange: (m) => setState(() => _gestureMode = m),
      onTapAt: (x, y) => _addRipple(_lastTouchX, _lastTouchY),
    ));
    widget.wsService.addListener(_onWs);
    // 初次校准：以服务端 IME 状态为准
    _imeTogglePending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.wsService.hasControl) {
        widget.wsService.sendMessage(CImeRefresh());
      }
    });
  }

  String _modPrefix() {
    var p = '';
    if (_modState['ctrl']!) p += 'ctrl+';
    if (_modState['shift']!) p += 'shift+';
    if (_modState['alt']!) p += 'alt+';
    return p;
  }

  void _sendKey(String k) {
    widget.wsService.sendMessage(CKey(_modPrefix() + k));
    Haptic.keyPress();
  }

  void _handleOskKey(String k) {
    if (_shiftState > 0) {
      widget.wsService.sendMessage(CKey('shift+$k'));
      _shiftState = 0;
    } else {
      widget.wsService.sendMessage(CKey(k));
    }
    Haptic.keyPress();
    setState(() {}); // 更新 UI（shift 状态等）
  }

  void _sendBs() {
    widget.wsService.sendMessage(CBackspace(1));
    Haptic.keyPress();
  }

  void _addRipple(double globalX, double globalY) {
    // 将全局坐标转换为触控板局部坐标
    final renderBox = _touchpadKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final local = renderBox.globalToLocal(Offset(globalX, globalY));
    setState(() {
      _ripples.add(_RippleData(key: UniqueKey(), x: local.dx, y: local.dy));
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _ripples.isNotEmpty) {
        setState(() => _ripples.removeAt(0));
      }
    });
  }

  void _startBsRepeat() {
    _bsRepeatStart?.cancel();
    _bsRepeatInterval?.cancel();
    _bsRepeatStart = Timer(const Duration(milliseconds: 400), () {
      _bsRepeatInterval =
          Timer.periodic(const Duration(milliseconds: 80), (_) => _sendBs());
    });
  }

  void _stopBsRepeat() {
    _bsRepeatStart?.cancel();
    _bsRepeatInterval?.cancel();
  }

  // IME 状态：只在 ws.imeStatus 实际变化时更新，不做无差别覆盖
  bool _imeZh = false;
  String _lastServerIme = 'en';
  // debounce: 用户手动切换后，短暂忽略服务端旧状态
  bool _imeTogglePending = false;
  bool _imeToggleExpected = false;
  int _imeToggleSentAt = 0;

  void _onWs() {
    if (!mounted) return;
    final ws = widget.wsService;
    if (!ws.isConnected && ws.state != ConnState.waitingAuth) {
      _showDisconnect();
    }
    // 只在 ws.imeStatus 真正变化时（即收到新的 ime_init 消息）才处理
    final serverIme = ws.imeStatus;
    if (serverIme == _lastServerIme) return; // 不是 ime_init 变化，忽略
    _lastServerIme = serverIme;

    final serverZh = serverIme == 'zh';
    // debounce：toggle 发出后 500ms 内，忽略服务端推送的旧状态
    if (_imeTogglePending && DateTime.now().millisecondsSinceEpoch - _imeToggleSentAt < 500) {
      if (serverZh != _imeToggleExpected) return; // 旧状态，忽略
      _imeTogglePending = false; // 收到期望的新状态，清除 pending
    }
    _imeZh = serverZh;
    setState(() {});
  }

  double _sensitivity = 0.5;

  Future<void> _loadSensitivity() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble('sensitivity') ?? 0.5;
    _sensitivity = v;
    GestureEngine.setScrollSensitivity(v);
    GestureEngine.setMoveSensitivity(0.5 + v * 2.5);
  }

  Future<void> _saveSensitivity(double v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('sensitivity', v);
  }

  void _showSensitivitySlider() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('鼠标灵敏度'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: _sensitivity,
                min: 0.1,
                max: 1.0,
                divisions: 18,
                label: '${(_sensitivity * 100).round()}%',
                activeColor: const Color(0xFF2395f3),
                onChanged: (v) {
                  setDialogState(() => _sensitivity = v);
                  GestureEngine.setScrollSensitivity(v);
                  GestureEngine.setMoveSensitivity(0.5 + v * 2.5);
                  _saveSensitivity(v);
                },
              ),
              Text('${(_sensitivity * 100).round()}%',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDisconnect() {
    widget.wsService.removeListener(_onWs);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('连接断开'),
        content: Text(widget.wsService.errorMessage ?? '连接已断开'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
            child: const Text('返回首页'),
          ),
          if (widget.wsService.hasEverControlled)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                widget.wsService.addListener(_onWs);
              },
              child: const Text('等待重连'),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _bsRepeatStart?.cancel();
    _bsRepeatInterval?.cancel();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    widget.wsService.removeListener(_onWs);
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 等横屏生效再渲染，避免闪烁
    if (!_ready) {
      return const Scaffold(
          backgroundColor: Color(0xFFeef4fd),
          body: Center(child: SizedBox()));
    }

    final screenW = MediaQuery.of(context).size.width;
    final fkWidth = _fkVisible ? screenW * 0.19 : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFeef4fd),
      body: Column(children: [
          _buildTopBar(),
          Expanded(
            child: Row(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Cubic(0.4, 0, 0.2, 1),
                width: fkWidth,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: _fkVisible ? _buildFkPanel() : null,
              ),
              Expanded(
                child: Column(children: [
                  Expanded(child: _buildTouchpad()),
                  // OSK 滑入动画（匹配网页版 transform: translateY(100%) → 0）
                  ClipRect(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: _oskVisible ? null : 0,
                        child: _buildOsk(),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ]),
      );
    }

  // ═══════════════════════════════════════════════════════════════
  // 顶栏
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTopBar() {
    final ok = widget.wsService.isConnected;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
            bottom: BorderSide(color: const Color(0xFFc4d9f0), width: 1)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1446a0).withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(children: [
        Image.asset('assets/icon.png', width: 22, height: 22),
        const SizedBox(width: 6),
        const Text('NexusPad',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF003472),
                letterSpacing: 0.6)),
        Expanded(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: ok
                    ? const Color(0xFF34a853).withValues(alpha: 0.1)
                    : const Color(0xFFeef4fd),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ok
                            ? const Color(0xFF34a853)
                            : const Color(0xFF6e8aa8))),
                const SizedBox(width: 6),
                Text(ok ? '已连接' : '已断开',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: ok
                            ? const Color(0xFF34a853)
                            : const Color(0xFF6e8aa8))),
              ]),
            ),
          ),
        ),
        // 鼠标灵敏度按钮（替代刷新按钮）
        _topBtn('🖱', onTap: () => _showSensitivitySlider()),
        const SizedBox(width: 5),
        _topBtn('Fn',
            active: _fkVisible,
            onTap: () => setState(() => _fkVisible = !_fkVisible)),
        const SizedBox(width: 5),
        _topBtn('⌨',
            active: _oskVisible,
            onTap: () {
              setState(() => _oskVisible = !_oskVisible);
              // 清除 debounce，让服务端自动推送的 IME 状态能正常更新
              _imeTogglePending = false;
            }),
      ]),
    );
  }

  Widget _topBtn(String text, {bool active = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 26,
        constraints: const BoxConstraints(minWidth: 34),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2395f3) : const Color(0xFFddeaf8),
          border: Border.all(
              color: active ? const Color(0xFF1565c0) : const Color(0xFFc4d9f0)),
          borderRadius: BorderRadius.circular(7),
          boxShadow: active
              ? [BoxShadow(
                  color: const Color(0xFF2395f3).withValues(alpha: 0.30),
                  blurRadius: 7)]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xFF6e8aa8))),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // FK 面板
  // ═══════════════════════════════════════════════════════════════

  Widget _buildFkPanel() {
    return GestureDetector(
      onTap: () {},
      onPanStart: (_) {},
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFeef4fd),
          border: Border(
              right: BorderSide(color: const Color(0xFFc4d9f0), width: 1)),
        ),
        child: SingleChildScrollView(
          child: Column(children: [
            _fkGroup([
              _fkKey('Esc', 'Escape'),
              _fkKey('Tab', 'Tab'),
              _fkKey('Del', 'Delete'),
            ]),
            const Divider(height: 12, color: Color(0xFFdeeaf8)),
            _fkGroup([
              _fkKey('↑', 'Up', isArrow: true),
              Row(children: [
                Expanded(child: _fkKey('←', 'Left', isArrow: true)),
                const SizedBox(width: 3),
                Expanded(child: _fkKey('↓', 'Down', isArrow: true)),
                const SizedBox(width: 3),
                Expanded(child: _fkKey('→', 'Right', isArrow: true)),
              ]),
            ]),
            const Divider(height: 12, color: Color(0xFFdeeaf8)),
            _fkGroup([
              _fkMod('Ctrl', 'ctrl'),
              _fkMod('Shift', 'shift'),
              _fkMod('Alt', 'alt'),
            ]),
            const Divider(height: 12, color: Color(0xFFdeeaf8)),
            _fkComboGroup(),
          ]),
        ),
      ),
    );
  }

  Widget _fkGroup(List<Widget> children) => Column(children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 3),
          children[i],
        ],
      ]);

  // FK 按键（带阴影）
  Widget _fkKey(String label, String key, {bool isArrow = false}) {
    return GestureDetector(
      onTap: () => _sendKey(key),
      child: Container(
        height: 29,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFc4d9f0)),
          borderRadius: BorderRadius.circular(7),
          boxShadow: _keyShadow,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: isArrow ? 12 : 10,
                fontWeight: isArrow ? FontWeight.w800 : FontWeight.w600,
                color: const Color(0xFF1a2e4a))),
      ),
    );
  }

  Widget _fkMod(String label, String mod) {
    final active = _modState[mod] ?? false;
    return GestureDetector(
      onTap: () {
        setState(() => _modState[mod] = !_modState[mod]!);
        Haptic.keyPress();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 29,
        width: double.infinity,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2395f3) : Colors.white,
          border: Border.all(
              color: active ? const Color(0xFF1565c0) : const Color(0xFFc4d9f0)),
          borderRadius: BorderRadius.circular(7),
          boxShadow: active
              ? [BoxShadow(
                  color: const Color(0xFF2395f3).withValues(alpha: 0.32),
                  blurRadius: 8, offset: const Offset(0, 2))]
              : _keyShadow,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : const Color(0xFF1a2e4a))),
      ),
    );
  }

  Widget _fkComboGroup() {
    const combos = [
      ['C', 'ctrl+c'], ['V', 'ctrl+v'], ['X', 'ctrl+x'],
      ['Z', 'ctrl+z'], ['A', 'ctrl+a'], ['S', 'ctrl+s'],
    ];
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: combos.map((c) {
        return SizedBox(
          width: 56,
          height: 28,
          child: GestureDetector(
            onTap: () {
              widget.wsService.sendMessage(CKey(c[1]));
              Haptic.keyPress();
            },
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFd5e7f7),
                border: Border.all(
                    color: const Color(0xFFaac8e4)),
                borderRadius: BorderRadius.circular(7),
                boxShadow: _keyShadow,
              ),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('⌃',
                        style: TextStyle(
                            fontSize: 7,
                            color: const Color(0xFF6e8aa8).withValues(alpha: 0.7),
                            height: 1)),
                    Text(c[0],
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6e8aa8))),
                  ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 触控板
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTouchpad() {
    return Listener(
      onPointerDown: (e) {
        _lastTouchX = e.position.dx;
        _lastTouchY = e.position.dy;
        _engine.handlePointerDown(e);
      },
      onPointerMove: (e) {
        _lastTouchX = e.position.dx;
        _lastTouchY = e.position.dy;
        _engine.handlePointerMove(e);
      },
      onPointerUp: _engine.handlePointerUp,
      onPointerCancel: _engine.handlePointerCancel,
      child: Container(
        key: _touchpadKey,
        color: Colors.white,
        child: Stack(children: [
          CustomPaint(painter: _TouchpadPainter(), size: Size.infinite),
          if (_gestureMode != GestureMode.idle &&
              _gestureMode != GestureMode.singleFinger)
            Positioned(top: 10, right: 12, child: _gestureTag()),
          Center(
            child: Text('触控板',
                style: TextStyle(
                    color: const Color(0xFFdeeaf8),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 4)),
          ),
          // 涟漪（跟随手指位置）
          ..._ripples.map((r) => Positioned(
                left: r.x - 22,
                top: r.y - 22,
                child: _RippleWidget(key: r.key),
              )),
        ]),
      ),
    );
  }

  Widget _gestureTag() {
    String text;
    switch (_gestureMode) {
      case GestureMode.scroll:
        text = '滚动';
        break;
      case GestureMode.pinch:
        text = '缩放';
        break;
      case GestureMode.drag:
        text = '拖动';
        break;
      default:
        text = '多点触控';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2395f3).withValues(alpha: 0.10),
        border: Border.all(
            color: const Color(0xFF2395f3).withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2395f3))),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // OSK 键盘 — 逐字匹配网页版 CSS 布局
  // .osk-row { gap: 3px } 所有键 flex:1 等宽
  // .osk-spacer-05 { flex: .5 }
  // .osk-layer { gap: 3px }
  // ═══════════════════════════════════════════════════════════════

  Widget _buildOsk() {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.47),
      decoration: BoxDecoration(
        color: const Color(0xFFeef4fd),
        border: Border(
            top: BorderSide(color: const Color(0xFFc4d9f0), width: 1.5)),
      ),
      padding: const EdgeInsets.all(5),
      child: _symLayer ? _buildSymLayer() : _buildAlphaLayer(),
    );
  }

  /// 构建带 3px 间距的行（匹配 CSS gap: 3px）
  List<Widget> _withGap(List<Widget> children) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) result.add(const SizedBox(width: 3));
      result.add(children[i]);
    }
    return result;
  }

  Widget _buildAlphaLayer() {
    // 用 LayoutBuilder 计算精确 flex 值，保证所有字母键等宽
    // Row 1: 10 keys, gap=3px, total gap=27
    // Row 2: 9 keys + 2 spacers(flex=0.5×key), gap=3px, total gap=30
    // Row 3: 9 keys, gap=3px, total gap=24
    // 令 Row1 key = 1, Row2 spacer = 0.5, Row3 key = 10/9
    return LayoutBuilder(
      builder: (context, constraints) {
        // Row 1 每个字母键的像素宽度
        final row1KeyW = (constraints.maxWidth - 27) / 10;
        // Row 3 flex: keyW = (W-24) / (9*flex+8) = row1KeyW → flex = ((W-24)/row1KeyW - 8) / 9
        final row3Flex = ((constraints.maxWidth - 24) / row1KeyW - 8) / 9;
        final r3f = (row3Flex * 10).round(); // 整数化
        return Column(children: [
          // Row 1: 10 keys × flex 10
          Expanded(child: Row(
            children: _withGap(
              ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p']
                  .map((k) => Expanded(flex: 10, child: _oskKeyWidget(k)))
                  .toList(),
            ),
          )),
          const SizedBox(height: 3),
          // Row 2: spacer(5) + 9 keys(flex:11) + spacer(5)
          // 总 flex = 5 + 99 + 5 = 109, key = 11/109 ≈ 0.1009
          // Row 1 key = 10/100 = 0.1000, 差异 < 1%
          Expanded(child: Row(
            children: _withGap([
              const Spacer(flex: 5),
              ...['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l']
                  .map((k) => Expanded(flex: 11, child: _oskKeyWidget(k))),
              const Spacer(flex: 5),
            ]),
          )),
          const SizedBox(height: 3),
          // Row 3: 9 keys × computed flex
          Expanded(child: Row(
            children: _withGap([
              Expanded(flex: r3f, child: _oskShiftKey()),
              ...['z', 'x', 'c', 'v', 'b', 'n', 'm']
                  .map((k) => Expanded(flex: r3f, child: _oskKeyWidget(k))),
              Expanded(flex: r3f, child: _oskBsWithRepeat()),
            ]),
          )),
          const SizedBox(height: 3),
          // Row 4: modifier keys (不同宽度，不需要统一)
          Expanded(child: Row(
            children: _withGap([
              Expanded(child: _oskModContainer('?123', onTap: () => setState(() => _symLayer = true))),
              Expanded(child: _oskLangKey()),
              Expanded(flex: 5, child: GestureDetector(
                onTap: () { widget.wsService.sendMessage(CKey('Space')); Haptic.keyPress(); },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFbcd1ec)),
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: _keyShadow,
                  ),
                  alignment: Alignment.center,
                  child: const Text('space',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6e8aa8), letterSpacing: 0.5)),
                ),
              )),
              Expanded(child: _oskModContainer(',', onTap: () {
                widget.wsService.sendMessage(CTypeText(','));
              })),
              Expanded(child: _oskModContainer('.', onTap: () {
                widget.wsService.sendMessage(CTypeText('.'));
              })),
              Expanded(child: _oskModContainer('⏎', onTap: () {
                widget.wsService.sendMessage(CKey('Return'));
              })),
            ]),
          )),
        ]);
      },
    );
  }

  Widget _buildSymLayer() {
    // 符号层所有键都是直接输入字符，用 CTypeText 而非 CKey
    return Column(children: [
      // Row 1: 1-0
      Expanded(child: Row(
        children: _withGap(
          ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']
              .map((k) => Expanded(child: _oskTextKey(k)))
              .toList(),
        ),
      )),
      const SizedBox(height: 3),
      // Row 2: !-)
      Expanded(child: Row(
        children: _withGap(
          ['!', '@', '#', '\$', '%', '^', '&', '*', '(', ')']
              .map((k) => Expanded(child: _oskTextKey(k)))
              .toList(),
        ),
      )),
      const SizedBox(height: 3),
      // Row 3: `-=[];'~\+
      Expanded(child: Row(
        children: _withGap(
          ['`', '-', '=', '[', ']', ';', "'", '~', '\\', '+']
              .map((k) => Expanded(child: _oskTextKey(k)))
              .toList(),
        ),
      )),
      const SizedBox(height: 3),
      // Row 4: ABC , . ? / | : " < >
      Expanded(child: Row(
        children: _withGap([
          Expanded(child: _oskModContainer('ABC', onTap: () => setState(() => _symLayer = false))),
          ...[',', '.', '?', '/', '|', ':', '"', '<', '>']
              .map((k) => Expanded(child: _oskTextKey(k))),
        ]),
      )),
    ]);
  }

  /// 符号层按键（用 CTypeText 直接输入字符，不走 CKey）
  Widget _oskTextKey(String k) {
    return _OskKeyButton(
      label: k,
      onTap: () {
        widget.wsService.sendMessage(CTypeText(k));
        Haptic.keyPress();
        setState(() {});
      },
    );
  }

  /// OSK 按键（带按压反馈 + CSS 阴影，无内边距）
  Widget _oskKeyWidget(String k) {
    final label = (_shiftState > 0 && k.length == 1) ? k.toUpperCase() : k;
    return _OskKeyButton(
      label: label,
      onTap: () => _handleOskKey(k),
    );
  }

  /// Shift 键（modifier 样式，简单 toggle，匹配网页版）
  Widget _oskShiftKey() {
    return GestureDetector(
      onTap: () {
        setState(() => _shiftState = _shiftState > 0 ? 0 : 1);
        Haptic.keyPress();
      },
      child: Container(
        decoration: BoxDecoration(
          color: _shiftState > 0 ? const Color(0xFF2395f3) : const Color(0xFFd5e7f7),
          border: Border.all(
              color: _shiftState > 0 ? const Color(0xFF1565c0) : const Color(0xFFaac8e4)),
          borderRadius: BorderRadius.circular(7),
          boxShadow: _shiftState > 0
              ? [BoxShadow(color: const Color(0xFF2395f3).withValues(alpha: 0.34), blurRadius: 6, offset: const Offset(0, 2))]
              : _modKeyShadow,
        ),
        alignment: Alignment.center,
        child: Text('⇧',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _shiftState > 0 ? Colors.white : const Color(0xFF6e8aa8))),
      ),
    );
  }

  /// 退格键（modifier 样式，等宽，带长按重复）
  Widget _oskBsWithRepeat() {
    return Listener(
      onPointerDown: (_) { _sendBs(); _startBsRepeat(); },
      onPointerUp: (_) => _stopBsRepeat(),
      onPointerCancel: (_) => _stopBsRepeat(),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFd5e7f7),
          border: Border.all(color: const Color(0xFFaac8e4)),
          borderRadius: BorderRadius.circular(7),
          boxShadow: _modKeyShadow,
        ),
        alignment: Alignment.center,
        child: const Text('⌫',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF6e8aa8))),
      ),
    );
  }

  /// 语言键（用 Listener 保证 100% 可靠触发）
  Widget _oskLangKey() {
    return _LangKeyWidget(
      imeZh: _imeZh,
      onTap: () {
        // 设置 debounce：toggle 后 500ms 内忽略服务端旧状态
        _imeTogglePending = true;
        _imeToggleExpected = !_imeZh;
        _imeToggleSentAt = DateTime.now().millisecondsSinceEpoch;
        widget.wsService.sendMessage(CImeToggle());
        setState(() => _imeZh = !_imeZh);
      },
    );
  }

  /// 通用 modifier 容器（?123、,、.、⏎ 等，带震动）
  Widget _oskModContainer(String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: () {
        onTap?.call();
        Haptic.keyPress();
      },
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFd5e7f7),
          border: Border.all(color: const Color(0xFFaac8e4)),
          borderRadius: BorderRadius.circular(7),
          boxShadow: _modKeyShadow,
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6e8aa8))),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// OSK 按键（带 .pressed 按压反馈）
// ═══════════════════════════════════════════════════════════════

class _OskKeyButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _OskKeyButton({required this.label, required this.onTap});

  @override
  State<_OskKeyButton> createState() => _OskKeyButtonState();
}

class _OskKeyButtonState extends State<_OskKeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        constraints: const BoxConstraints.expand(), // 填满 Expanded 分配的空间
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFFddeaf8) : Colors.white,
          border: Border.all(color: const Color(0xFFbcd1ec)),
          borderRadius: BorderRadius.circular(7),
          boxShadow: _pressed ? null : [
            const BoxShadow(
                color: Color(0xFF9dbedd), blurRadius: 0, offset: Offset(0, 1.5))
          ],
        ),
        transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.95, 0.95, 0.95, 1.0))
            : Matrix4.identity(),
        alignment: Alignment.center,
        child: Text(widget.label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1a2e4a))),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 涟漪（跟随手指位置）
// ═══════════════════════════════════════════════════════════════

class _RippleData {
  final Key key;
  final double x, y;
  _RippleData({required this.key, required this.x, required this.y});
}

class _RippleWidget extends StatefulWidget {
  const _RippleWidget({super.key});

  @override
  State<_RippleWidget> createState() => _RippleWidgetState();
}

class _RippleWidgetState extends State<_RippleWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380))
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Opacity(
          opacity: 0.4 * (1 - t),
          child: Transform.scale(
            scale: 0.2 + 1.6 * t,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF34a853).withValues(alpha: 0.3),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 语言键 Widget（直接用 Listener 保证 100% 可靠触发）
// ═══════════════════════════════════════════════════════════════

class _LangKeyWidget extends StatefulWidget {
  final bool imeZh;
  final VoidCallback onTap;
  const _LangKeyWidget({required this.imeZh, required this.onTap});

  @override
  State<_LangKeyWidget> createState() => _LangKeyWidgetState();
}

class _LangKeyWidgetState extends State<_LangKeyWidget> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        setState(() => _pressed = true);
        Haptic.keyPress();
        widget.onTap();
      },
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 50),
        constraints: const BoxConstraints.expand(),
        decoration: BoxDecoration(
          color: _pressed ? const Color(0xFFbcd0e8) : const Color(0xFFd5e7f7),
          border: Border.all(color: const Color(0xFFaac8e4)),
          borderRadius: BorderRadius.circular(7),
          boxShadow: _pressed
              ? null
              : [const BoxShadow(color: Color(0xFF90bad6), blurRadius: 0, offset: Offset(0, 1.5))],
        ),
        transform: _pressed
            ? (Matrix4.identity()..scaleByDouble(0.95, 0.95, 0.95, 1.0))
            : Matrix4.identity(),
        alignment: Alignment.center,
        child: Text(
          widget.imeZh ? '中/EN' : 'EN/中',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6e8aa8)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 触控板点阵
// ═══════════════════════════════════════════════════════════════

class _TouchpadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = const Color(0xAAc8dcfa).withValues(alpha: 0.7)
      ..strokeCap = StrokeCap.round;
    const sp = 20.0;
    for (double x = sp; x < size.width; x += sp) {
      for (double y = sp; y < size.height; y += sp) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }
    final bp = Paint()
      ..color = const Color(0xFFc4d9f0)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const bl = 14.0, m = 8.0;
    canvas.drawLine(Offset(m, m), Offset(m + bl, m), bp);
    canvas.drawLine(Offset(m, m), Offset(m, m + bl), bp);
    canvas.drawLine(Offset(size.width - m, m), Offset(size.width - m - bl, m), bp);
    canvas.drawLine(Offset(size.width - m, m), Offset(size.width - m, m + bl), bp);
    canvas.drawLine(Offset(m, size.height - m), Offset(m + bl, size.height - m), bp);
    canvas.drawLine(Offset(m, size.height - m), Offset(m, size.height - m - bl), bp);
    canvas.drawLine(Offset(size.width - m, size.height - m),
        Offset(size.width - m - bl, size.height - m), bp);
    canvas.drawLine(Offset(size.width - m, size.height - m),
        Offset(size.width - m, size.height - m - bl), bp);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
