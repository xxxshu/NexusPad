import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/gamepad_layout.dart';
import '../models/protocol.dart';
import '../services/ws_service.dart';
import '../utils/haptic.dart';
import 'custom_layout_editor_screen.dart';
import 'custom_gamepad_screen.dart';

/// 自定义布局列表页（竖屏）
class CustomLayoutListScreen extends StatefulWidget {
  final WsService wsService;
  const CustomLayoutListScreen({super.key, required this.wsService});

  @override
  State<CustomLayoutListScreen> createState() => _CustomLayoutListScreenState();
}

class _CustomLayoutListScreenState extends State<CustomLayoutListScreen> {
  List<GamepadLayout> _layouts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _loadLayouts();
  }

  Future<void> _loadLayouts() async {
    final layouts = await LayoutStorage.loadAll();
    setState(() {
      _layouts = layouts;
      _loading = false;
    });
  }

  void _createNew() async {
    Haptic.tap();
    final layout = GamepadLayout(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '新布局',
      createdAt: DateTime.now().toIso8601String(),
    );
    final result = await Navigator.of(context).push<GamepadLayout>(
      MaterialPageRoute(
        builder: (_) => CustomLayoutEditorScreen(layout: layout),
      ),
    );
    if (result != null) {
      await LayoutStorage.save(result);
      _loadLayouts();
    }
  }

  void _editLayout(GamepadLayout layout) async {
    Haptic.tap();
    final result = await Navigator.of(context).push<GamepadLayout>(
      MaterialPageRoute(
        builder: (_) => CustomLayoutEditorScreen(layout: layout.copy()),
      ),
    );
    if (result != null) {
      await LayoutStorage.save(result);
      _loadLayouts();
    }
  }

  void _useLayout(GamepadLayout layout) {
    Haptic.tap();
    // 发送自定义模式的 gc 消息
    widget.wsService.sendMessage(CGamepadConnect('custom'));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomGamepadScreen(
          wsService: widget.wsService,
          layout: layout,
        ),
      ),
    );
  }

  void _deleteLayout(GamepadLayout layout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除布局'),
        content: Text('确定要删除"${layout.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await LayoutStorage.delete(layout.id);
      _loadLayouts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFeef4fd),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1a2e4a)),
        ),
        title: const Text(
          '自定义布局',
          style: TextStyle(
            color: Color(0xFF1a2e4a),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 新建按钮
                _buildAddCard(),
                const SizedBox(height: 12),
                // 已有布局
                ..._layouts.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildLayoutCard(l),
                )),
                if (_layouts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        '还没有自定义布局\n点击上方"+"创建一个',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF6e8aa8), fontSize: 14),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildAddCard() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _createNew,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFc4d9f0),
              width: 2,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: const Column(
            children: [
              Icon(Icons.add_circle_outline, color: Color(0xFF2395f3), size: 36),
              SizedBox(height: 8),
              Text(
                '新建布局',
                style: TextStyle(
                  color: Color(0xFF2395f3),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLayoutCard(GamepadLayout layout) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _useLayout(layout),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFc4d9f0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1446a0).withValues(alpha: 0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2395f3).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune, color: Color(0xFF2395f3), size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      layout.name,
                      style: const TextStyle(
                        color: Color(0xFF1a2e4a),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${layout.elements.length} 个元素',
                      style: const TextStyle(
                        color: Color(0xFF6e8aa8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _editLayout(layout),
                icon: const Icon(Icons.edit, color: Color(0xFF6e8aa8), size: 20),
              ),
              IconButton(
                onPressed: () => _deleteLayout(layout),
                icon: const Icon(Icons.delete_outline, color: Color(0xFFe53935), size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
