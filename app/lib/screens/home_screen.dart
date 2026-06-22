import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ws_service.dart';
import '../utils/haptic.dart';
import 'gamepad_select_screen.dart';
import 'touchpad_screen.dart';

/// 模式选择页（竖屏）—— 连接成功后进入
class HomeScreen extends StatefulWidget {
  final WsService wsService;
  const HomeScreen({super.key, required this.wsService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFeef4fd),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF003472).withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset('assets/icon.png', width: 80, height: 80),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'NexusPad',
                  style: TextStyle(
                    color: Color(0xFF003472),
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '手机变身电脑外设',
                  style: TextStyle(
                    color: Color(0xFF6e8aa8),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 48),
                // 触控板键盘
                _ModeCard(
                  icon: Icons.mouse,
                  title: '触控板键盘',
                  subtitle: '鼠标移动 · 点击 · 滚动 · 缩放',
                  color: const Color(0xFF2395f3),
                  onTap: () {
                    Haptic.tap();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TouchpadScreen(wsService: widget.wsService),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // 游戏手柄
                _ModeCard(
                  icon: Icons.gamepad,
                  title: '游戏手柄',
                  subtitle: 'Xbox 360 · PS5 · 自定义布局',
                  color: const Color(0xFF4a7c59),
                  onTap: () {
                    Haptic.tap();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GamepadSelectScreen(wsService: widget.wsService),
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

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
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
