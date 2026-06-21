import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gamepad_layout.dart';
import '../utils/haptic.dart';

/// 可添加的元素类型
class _ToolItem {
  final String type; // "button" | "joystick" | "touchpad"
  final String? buttonId;
  final String label;
  final IconData icon;

  const _ToolItem({
    required this.type,
    this.buttonId,
    required this.label,
    required this.icon,
  });
}

const _tools = <_ToolItem>[
  // 按钮
  _ToolItem(type: 'button', buttonId: 'a', label: 'A', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'b', label: 'B', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'x', label: 'X', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'y', label: 'Y', icon: Icons.circle),
  _ToolItem(type: 'button', buttonId: 'lb', label: 'LB', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'rb', label: 'RB', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'lt', label: 'LT', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'rt', label: 'RT', icon: Icons.rectangle),
  _ToolItem(type: 'button', buttonId: 'up', label: '↑', icon: Icons.arrow_upward),
  _ToolItem(type: 'button', buttonId: 'down', label: '↓', icon: Icons.arrow_downward),
  _ToolItem(type: 'button', buttonId: 'left', label: '←', icon: Icons.arrow_back),
  _ToolItem(type: 'button', buttonId: 'right', label: '→', icon: Icons.arrow_forward),
  _ToolItem(type: 'button', buttonId: 'ls', label: 'LS', icon: Icons.radio_button_checked),
  _ToolItem(type: 'button', buttonId: 'rs', label: 'RS', icon: Icons.radio_button_checked),
  _ToolItem(type: 'button', buttonId: 'back', label: 'Back', icon: Icons.crop_square),
  _ToolItem(type: 'button', buttonId: 'menu', label: 'Menu', icon: Icons.menu),
  _ToolItem(type: 'button', buttonId: 'guide', label: 'Guide', icon: Icons.home),
  // 摇杆
  _ToolItem(type: 'joystick', label: '左摇杆', icon: Icons.gamepad),
  _ToolItem(type: 'joystick', label: '右摇杆', icon: Icons.gamepad),
  // 触控板
  _ToolItem(type: 'touchpad', label: '触控板', icon: Icons.touch_app),
];

/// 自定义布局编辑器（横屏）
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

  @override
  void initState() {
    super.initState();
    _layout = widget.layout;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _addElement(_ToolItem tool) {
    Haptic.tap();
    final el = LayoutElement(
      type: tool.type,
      x: 0.5, // 居中
      y: 0.5,
      size: tool.type == 'joystick' ? 0.18 : 0.08,
      buttonId: tool.buttonId,
      label: tool.label,
      stickSide: tool.type == 'joystick'
          ? (tool.label.contains('左') ? 'left' : 'right')
          : null,
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
    // 弹出命名对话框
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController(text: _layout.name);
        return AlertDialog(
          title: const Text('保存布局'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '布局名称',
              hintText: '输入名称',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
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

    return Scaffold(
      backgroundColor: const Color(0xFF0f1a2e),
      body: SafeArea(
        child: Stack(
          children: [
            // 编辑画布
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _selectedIndex = null),
                child: CustomPaint(
                  painter: _GridPainter(),
                  child: Stack(
                    children: [
                      for (int i = 0; i < _layout.elements.length; i++)
                        _buildElementWidget(i, screenW, screenH),
                    ],
                  ),
                ),
              ),
            ),

            // 顶部工具栏
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),

            // 底部工具栏
            if (_showToolbar)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomToolbar(),
              ),

            // 选中元素的属性编辑
            if (_selectedIndex != null)
              _buildPropertyPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF162240),
        border: Border(bottom: BorderSide(color: Color(0xFF2a4a70), width: 1)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.close, color: Color(0xFF8ab4e0), size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            _layout.name,
            style: const TextStyle(color: Color(0xFF8ab4e0), fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(
            '  (${_layout.elements.length} 个元素)',
            style: const TextStyle(color: Color(0xFF6e8aa8), fontSize: 12),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _showToolbar = !_showToolbar),
            child: Icon(
              _showToolbar ? Icons.keyboard_hide : Icons.keyboard,
              color: const Color(0xFF8ab4e0),
              size: 18,
            ),
          ),
          const SizedBox(width: 16),
          if (_selectedIndex != null)
            GestureDetector(
              onTap: _deleteSelected,
              child: const Icon(Icons.delete, color: Color(0xFFe53935), size: 18),
            ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: _save,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF2395f3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('保存', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF162240),
        border: Border(top: BorderSide(color: Color(0xFF2a4a70), width: 1)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _tools.map((tool) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => _addElement(tool),
              child: Container(
                width: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF1a2d4a),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2a4a70), width: 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(tool.icon, color: const Color(0xFF4a9eff), size: 18),
                    const SizedBox(height: 2),
                    Text(
                      tool.label,
                      style: const TextStyle(color: Color(0xFF8ab4e0), fontSize: 9),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
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
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1e3352),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF4a9eff) : const Color(0xFF2a4a70),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            el.stickSide == 'left' ? 'L' : 'R',
            style: const TextStyle(color: Color(0xFF6e8aa8), fontSize: 14),
          ),
        ),
      );
    } else if (el.type == 'touchpad') {
      child = Container(
        width: size * 1.5,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF1e3352),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF4a9eff) : const Color(0xFF2a4a70),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: const Center(
          child: Icon(Icons.touch_app, color: Color(0xFF6e8aa8), size: 20),
        ),
      );
    } else {
      // button
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF2a3f5f),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? const Color(0xFF4a9eff) : const Color(0xFF3a5a80),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            el.label ?? el.buttonId ?? '?',
            style: const TextStyle(color: Color(0xFF8ab4e0), fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Positioned(
      left: el.type == 'touchpad' ? left - size * 0.25 : left,
      top: top,
      child: GestureDetector(
        onTap: () {
          Haptic.tap();
          setState(() => _selectedIndex = index);
        },
        onPanUpdate: (details) {
          setState(() {
            el.x = (el.x + details.delta.dx / screenW).clamp(0.05, 0.95);
            el.y = (el.y + details.delta.dy / screenH).clamp(0.05, 0.95);
          });
        },
        child: child,
      ),
    );
  }

  Widget _buildPropertyPanel() {
    if (_selectedIndex == null || _selectedIndex! >= _layout.elements.length) {
      return const SizedBox.shrink();
    }
    final el = _layout.elements[_selectedIndex!];

    return Positioned(
      right: 12,
      top: 50,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF162240),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2a4a70), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${el.type} - ${el.label ?? el.buttonId ?? ""}',
              style: const TextStyle(color: Color(0xFF8ab4e0), fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            // 大小调节
            const Text('大小', style: TextStyle(color: Color(0xFF6e8aa8), fontSize: 11)),
            Slider(
              value: el.size,
              min: 0.04,
              max: 0.3,
              onChanged: (v) => setState(() => el.size = v),
              activeColor: const Color(0xFF2395f3),
            ),
            // 触控板映射
            if (el.type == 'touchpad') ...[
              const Text('映射到', style: TextStyle(color: Color(0xFF6e8aa8), fontSize: 11)),
              const SizedBox(height: 4),
              Row(
                children: ['left', 'right'].map((side) {
                  final selected = el.mapTo == side;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => el.mapTo = side),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? const Color(0xFF2395f3) : const Color(0xFF1a2d4a),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            side == 'left' ? '左摇杆' : '右摇杆',
                            style: TextStyle(
                              color: selected ? Colors.white : const Color(0xFF6e8aa8),
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              const Text('灵敏度', style: TextStyle(color: Color(0xFF6e8aa8), fontSize: 11)),
              Slider(
                value: el.sensitivity ?? 1.0,
                min: 0.3,
                max: 3.0,
                onChanged: (v) => setState(() => el.sensitivity = v),
                activeColor: const Color(0xFF2395f3),
              ),
            ],
            const SizedBox(height: 4),
            // 删除按钮
            GestureDetector(
              onTap: _deleteSelected,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFe53935).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: Text('删除', style: TextStyle(color: Color(0xFFe53935), fontSize: 12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1a2d4a).withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
