import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/gamepad_layout.dart';
import '../utils/haptic.dart';
import '../utils/neu_tokens.dart';

/// 可添加的元素类型
class _ToolItem {
  final String type;
  final String? buttonId;
  final String label;
  final IconData icon;
  const _ToolItem({required this.type, this.buttonId, required this.label, required this.icon});
}

const _xboxTools = <_ToolItem>[
  _ToolItem(type: 'button', buttonId: 'a', label: 'A', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'b', label: 'B', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'x', label: 'X', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'y', label: 'Y', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'lb', label: 'LB', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'rb', label: 'RB', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'lt', label: 'LT', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'rt', label: 'RT', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'up', label: '▲', icon: Icons.arrow_upward),
  _ToolItem(type: 'button', buttonId: 'down', label: '▼', icon: Icons.arrow_downward),
  _ToolItem(type: 'button', buttonId: 'left', label: '◀', icon: Icons.arrow_back),
  _ToolItem(type: 'button', buttonId: 'right', label: '▶', icon: Icons.arrow_forward),
  _ToolItem(type: 'button', buttonId: 'ls', label: 'LS', icon: Icons.radio_button_checked),
  _ToolItem(type: 'button', buttonId: 'rs', label: 'RS', icon: Icons.radio_button_checked),
  _ToolItem(type: 'button', buttonId: 'back', label: 'Back', icon: Icons.crop_square),
  _ToolItem(type: 'button', buttonId: 'menu', label: 'Menu', icon: Icons.menu),
  _ToolItem(type: 'joystick', label: '左摇杆', icon: Icons.gamepad),
  _ToolItem(type: 'joystick', label: '右摇杆', icon: Icons.gamepad),
  _ToolItem(type: 'touchpad', label: '触控板', icon: Icons.touch_app),
];

const _ps5Tools = <_ToolItem>[
  _ToolItem(type: 'button', buttonId: 'a', label: '✕', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'b', label: '○', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'x', label: '□', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'y', label: '△', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'lb', label: 'L1', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'rb', label: 'R1', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'lt', label: 'L2', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'rt', label: 'R2', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'up', label: '▲', icon: Icons.arrow_upward),
  _ToolItem(type: 'button', buttonId: 'down', label: '▼', icon: Icons.arrow_downward),
  _ToolItem(type: 'button', buttonId: 'left', label: '◀', icon: Icons.arrow_back),
  _ToolItem(type: 'button', buttonId: 'right', label: '▶', icon: Icons.arrow_forward),
  _ToolItem(type: 'button', buttonId: 'ls', label: 'L3', icon: Icons.radio_button_checked),
  _ToolItem(type: 'button', buttonId: 'rs', label: 'R3', icon: Icons.radio_button_checked),
  _ToolItem(type: 'button', buttonId: 'back', label: 'Create', icon: Icons.crop_square),
  _ToolItem(type: 'button', buttonId: 'menu', label: 'Options', icon: Icons.menu),
  _ToolItem(type: 'joystick', label: '左摇杆', icon: Icons.gamepad),
  _ToolItem(type: 'joystick', label: '右摇杆', icon: Icons.gamepad),
  _ToolItem(type: 'touchpad', label: '触控板', icon: Icons.touch_app),
];

/// 自定义布局编辑器（横屏）— 拟态风格
class CustomLayoutEditorScreen extends StatefulWidget {
  final GamepadLayout layout;
  const CustomLayoutEditorScreen({super.key, required this.layout});

  @override
  State<CustomLayoutEditorScreen> createState() => _CustomLayoutEditorScreenState();
}

class _CustomLayoutEditorScreenState extends State<CustomLayoutEditorScreen> {
  late GamepadLayout _layout;
  int? _selectedIndex;
  bool _showToolbar = true;
  bool _isXboxMode = true; // Xbox/PS5 按钮集切换

  // 笔按钮位置 (屏幕比例)，独立持久化
  double _penX = 0.5;
  double _penY = 0.12;

  @override
  void initState() {
    super.initState();
    _layout = widget.layout;
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadPenPosition();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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

  void _addElement(_ToolItem tool) {
    Haptic.tap();
    final el = LayoutElement(
      type: tool.type, x: 0.5, y: 0.5,
      size: tool.type == 'joystick' ? 0.18 : 0.08,
      buttonId: tool.buttonId, label: tool.label,
      stickSide: tool.type == 'joystick' ? (tool.label.contains('左') ? 'left' : 'right') : null,
      mapTo: tool.type == 'touchpad' ? 'right' : null,
      sensitivity: tool.type == 'touchpad' ? 1.0 : null,
    );
    setState(() {
      _layout.elements.add(el);
      _selectedIndex = _layout.elements.length - 1;
    });
  }

  void _deleteSelected() {
    if (_selectedIndex == null) return;
    Haptic.tap();
    setState(() {
      _layout.elements.removeAt(_selectedIndex!);
      _selectedIndex = null;
    });
  }

  void _save() async {
    Haptic.tap();
    final name = await showDialog<String>(context: context, builder: (ctx) {
      final controller = TextEditingController(text: _layout.name);
      return AlertDialog(
        title: const Text('保存布局'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: '布局名称', hintText: '输入名称'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('保存')),
        ],
      );
    });
    if (name != null && name.isNotEmpty) {
      _layout.name = name;
      if (!mounted) return;
      Navigator.of(context).pop(_layout);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final penSize = screenH * 0.12;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment(-0.8, -1.0), end: Alignment(0.6, 1.0), colors: [Color(0xFFD8EAF8), Color(0xFFC3D8EC)]),
        ),
        child: Stack(children: [
          // 编辑画布
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _selectedIndex = null),
              child: CustomPaint(painter: _GridPainter(), child: Stack(children: [
                for (int i = 0; i < _layout.elements.length; i++)
                  _buildElementWidget(i, screenW, screenH),
                // 笔按钮 (永久，可拖动，不可删除)
                _buildPenButton(screenW, screenH, penSize),
              ])),
            ),
          ),

          // 顶部工具栏 (拟态)
          Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

          // 底部工具栏 (拟态)
          if (_showToolbar) Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomToolbar()),

          // 属性面板
          if (_selectedIndex != null) _buildPropertyPanel(),
        ]),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: neuBg.withValues(alpha: 0.9),
        boxShadow: const [BoxShadow(color: neuDs, blurRadius: 6, offset: Offset(0, 2)), BoxShadow(color: neuLs, blurRadius: 4, offset: Offset(0, -1))],
      ),
      child: Row(children: [
        _neuIconBtn(Icons.close, () => Navigator.of(context).pop()),
        const SizedBox(width: 12),
        Text(_layout.name, style: const TextStyle(color: _textColor, fontSize: 14, fontWeight: FontWeight.w600)),
        Text('  (${_layout.elements.length} 个元素)', style: const TextStyle(color: neuMuted, fontSize: 12)),
        const Spacer(),
        _neuIconBtn(_showToolbar ? Icons.keyboard_hide : Icons.keyboard, () => setState(() => _showToolbar = !_showToolbar)),
        const SizedBox(width: 12),
        if (_selectedIndex != null) _neuIconBtn(Icons.delete, _deleteSelected, color: const Color(0xFFE53935)),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _save,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: neuAc, borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: neuAg, blurRadius: 12), const BoxShadow(color: Color(0x2E000000), blurRadius: 4, offset: Offset(1, 1))],
            ),
            child: const Text('保存', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _neuIconBtn(IconData icon, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: neuBg,
          boxShadow: const [BoxShadow(color: neuDs, blurRadius: 6, offset: Offset(2, 2)), BoxShadow(color: neuLs, blurRadius: 5, offset: Offset(-2, -2))],
        ),
        child: Center(child: Icon(icon, color: color ?? neuMuted, size: 16)),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    final tools = _isXboxMode ? _xboxTools : _ps5Tools;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: neuBg.withValues(alpha: 0.9),
        boxShadow: const [BoxShadow(color: neuDs, blurRadius: 6, offset: Offset(0, -2)), BoxShadow(color: neuLs, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Row(children: [
        // Xbox/PS5 切换按钮
        GestureDetector(
          onTap: () => setState(() => _isXboxMode = !_isXboxMode),
          child: Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: neuBg, borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: neuDs, blurRadius: 6, offset: Offset(2, 2)), BoxShadow(color: neuLs, blurRadius: 5, offset: Offset(-2, -2))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_isXboxMode ? Icons.gamepad : Icons.gamepad_outlined, color: neuAc, size: 16),
              const SizedBox(height: 2),
              Text(_isXboxMode ? 'Xbox' : 'PS5', style: const TextStyle(color: neuMuted, fontSize: 8, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        // 工具列表
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: tools.map((tool) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () => _addElement(tool),
                child: Container(
                  width: 48,
                  decoration: BoxDecoration(
                    color: neuBg, borderRadius: BorderRadius.circular(8),
                    boxShadow: const [BoxShadow(color: neuDs, blurRadius: 6, offset: Offset(2, 2)), BoxShadow(color: neuLs, blurRadius: 5, offset: Offset(-2, -2))],
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(tool.icon, color: neuAc, size: 16),
                    const SizedBox(height: 2),
                    Text(tool.label, style: const TextStyle(color: neuMuted, fontSize: 8), overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ),
            )).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildElementWidget(int index, double screenW, double screenH) {
    final el = _layout.elements[index];
    final isSelected = _selectedIndex == index;
    final size = el.size * screenH;
    final left = el.x * screenW - size / 2;
    final top = el.y * screenH - size / 2;

    Widget child;
    if (el.type == 'joystick') {
      child = Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: neuBg,
          border: isSelected ? Border.all(color: neuAc, width: 2) : null,
          boxShadow: const [BoxShadow(color: neuDs, blurRadius: 10, offset: Offset(4, 4)), BoxShadow(color: neuLs, blurRadius: 9, offset: Offset(-3, -3))],
        ),
        child: Center(child: Text(el.stickSide == 'left' ? 'L' : 'R', style: const TextStyle(color: neuMuted, fontSize: 14, fontWeight: FontWeight.w700))),
      );
    } else if (el.type == 'touchpad') {
      child = Container(
        width: size * 1.5, height: size,
        decoration: BoxDecoration(
          color: neuBg, borderRadius: BorderRadius.circular(10),
          border: isSelected ? Border.all(color: neuAc, width: 2) : null,
          boxShadow: const [BoxShadow(color: neuDs, blurRadius: 10, offset: Offset(4, 4)), BoxShadow(color: neuLs, blurRadius: 9, offset: Offset(-3, -3))],
        ),
        child: const Center(child: Icon(Icons.touch_app, color: neuMuted, size: 20)),
      );
    } else {
      final isFace = el.buttonId != null && ['a', 'b', 'x', 'y'].contains(el.buttonId);
      final faceColor = isFace ? _faceColors[el.buttonId]! : neuAc;
      child = Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle, color: neuBg,
          border: Border.all(color: isSelected ? neuAc : faceColor.withValues(alpha: 0.27), width: isSelected ? 2 : 2.5),
          boxShadow: const [BoxShadow(color: neuDs, blurRadius: 10, offset: Offset(4, 4)), BoxShadow(color: neuLs, blurRadius: 9, offset: Offset(-3, -3))],
        ),
        child: Center(child: Text(
          el.label ?? el.buttonId ?? '?',
          style: TextStyle(color: isFace ? faceColor : neuMuted, fontSize: 12, fontWeight: FontWeight.w700),
        )),
      );
    }

    return Positioned(
      left: el.type == 'touchpad' ? left - size * 0.25 : left,
      top: top,
      child: GestureDetector(
        onTap: () { Haptic.tap(); setState(() => _selectedIndex = index); },
        onPanUpdate: (d) { setState(() { el.x = (el.x + d.delta.dx / screenW).clamp(0.05, 0.95); el.y = (el.y + d.delta.dy / screenH).clamp(0.05, 0.95); }); },
        child: child,
      ),
    );
  }

  Widget _buildPenButton(double screenW, double screenH, double size) {
    return Positioned(
      left: _penX * screenW - size / 2,
      top: _penY * screenH - size / 2,
      child: GestureDetector(
        onTap: () {
          // Short press = Guide button (same as Xbox/PS home button)
          Haptic.tap();
        },
        onPanUpdate: (d) {
          setState(() {
            _penX = (_penX + d.delta.dx / screenW).clamp(0.05, 0.95);
            _penY = (_penY + d.delta.dy / screenH).clamp(0.05, 0.95);
          });
        },
        onPanEnd: (_) => _savePenPosition(),
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [neuAc, Color(0xFF5EC3FF)]),
            boxShadow: [
              BoxShadow(color: neuAg, blurRadius: 24),
              const BoxShadow(color: neuDs, blurRadius: 9, offset: Offset(3, 3)),
              BoxShadow(color: neuLs, blurRadius: 6, offset: const Offset(-2, -2)),
            ],
          ),
          child: const Center(child: Icon(Icons.edit, color: Colors.white, size: 20)),
        ),
      ),
    );
  }

  static const _textColor = Color(0xFF16304A);
  static const _faceColors = {
    'a': Color(0xFF43A047), 'b': Color(0xFFE53935), 'x': Color(0xFF1B8EF2), 'y': Color(0xFFF5A623),
  };

  Widget _buildPropertyPanel() {
    if (_selectedIndex == null || _selectedIndex! >= _layout.elements.length) return const SizedBox.shrink();
    final el = _layout.elements[_selectedIndex!];

    return Positioned(
      right: 12, top: 50,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: neuBg.withValues(alpha: 0.95), borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: neuDs, blurRadius: 10, offset: Offset(4, 4)), BoxShadow(color: neuLs, blurRadius: 9, offset: Offset(-3, -3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${el.type} - ${el.label ?? el.buttonId ?? ""}', style: const TextStyle(color: _textColor, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('大小', style: TextStyle(color: neuMuted, fontSize: 11)),
          Slider(value: el.size, min: 0.04, max: 0.3, onChanged: (v) => setState(() => el.size = v), activeColor: neuAc),
          if (el.type == 'touchpad') ...[
            const Text('映射到', style: TextStyle(color: neuMuted, fontSize: 11)),
            const SizedBox(height: 4),
            Row(children: ['left', 'right'].map((side) {
              final selected = el.mapTo == side;
              return Expanded(child: GestureDetector(
                onTap: () => setState(() => el.mapTo = side),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(color: selected ? neuAc : neuBg, borderRadius: BorderRadius.circular(6),
                    boxShadow: selected ? [BoxShadow(color: neuAg, blurRadius: 8)] : const [BoxShadow(color: neuDs, blurRadius: 4, offset: Offset(2, 2)), BoxShadow(color: neuLs, blurRadius: 3, offset: Offset(-1, -1))]),
                  child: Center(child: Text(side == 'left' ? '左摇杆' : '右摇杆', style: TextStyle(color: selected ? Colors.white : neuMuted, fontSize: 11))),
                ),
              ));
            }).toList()),
            const SizedBox(height: 6),
            const Text('灵敏度', style: TextStyle(color: neuMuted, fontSize: 11)),
            Slider(value: el.sensitivity ?? 1.0, min: 0.3, max: 3.0, onChanged: (v) => setState(() => el.sensitivity = v), activeColor: neuAc),
          ],
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _deleteSelected,
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(color: const Color(0xFFE53935).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: const Center(child: Text('删除', style: TextStyle(color: Color(0xFFE53935), fontSize: 12))),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = neuDs.withValues(alpha: 0.3)..strokeWidth = 0.5;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint); }
    for (double y = 0; y < size.height; y += spacing) { canvas.drawLine(Offset(0, y), Offset(size.width, y), paint); }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
