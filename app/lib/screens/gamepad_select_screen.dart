import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/protocol.dart';
import '../services/ws_service.dart';
import '../utils/haptic.dart';
import 'custom_layout_list_screen.dart';
import 'gamepad_screen.dart';

/// 手柄类型选择页（竖屏）
class GamepadSelectScreen extends StatefulWidget {
  final WsService wsService;
  const GamepadSelectScreen({super.key, required this.wsService});

  @override
  State<GamepadSelectScreen> createState() => _GamepadSelectScreenState();
}

class _GamepadSelectScreenState extends State<GamepadSelectScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _selectGamepad(String type) {
    Haptic.tap();
    widget.wsService.sendMessage(CGamepadConnect(type));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GamepadScreen(wsService: widget.wsService, mode: type),
      ),
    );
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
          '选择手柄布局',
          style: TextStyle(
            color: Color(0xFF1a2e4a),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _GamepadCard(
                  icon: Icons.gamepad,
                  title: 'Xbox 360 Controller',
                  subtitle: 'A B X Y · LB RB · 左右摇杆 · 十字键',
                  color: const Color(0xFF107C10),
                  onTap: () => _selectGamepad('xbox'),
                ),
                const SizedBox(height: 16),
                _GamepadCard(
                  icon: Icons.gamepad,
                  title: 'PS5 DualSense',
                  subtitle: '× ○ □ △ · L1 R1 · 左右摇杆 · 十字键',
                  color: const Color(0xFF003087),
                  onTap: () => _selectGamepad('ps'),
                ),
                const SizedBox(height: 16),
                _GamepadCard(
                  icon: Icons.tune,
                  title: '自定义布局',
                  subtitle: '创建你自己的手柄方案',
                  color: const Color(0xFF6e8aa8),
                  onTap: () {
                    Haptic.tap();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CustomLayoutListScreen(wsService: widget.wsService),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GamepadCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _GamepadCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
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
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF1a2e4a),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF6e8aa8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFc4d9f0)),
            ],
          ),
        ),
      ),
    );
  }
}
