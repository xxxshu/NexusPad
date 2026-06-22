import 'package:flutter/material.dart';

/// 设置页（竖屏）
/// 震动开关、陀螺仪开关 + 灵敏度滑块
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _vibrationEnabled = true;
  bool _gyroEnabled = false;
  double _gyroSensX = 0.5;
  double _gyroSensY = 0.5;

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
          '设置',
          style: TextStyle(
            color: Color(0xFF1a2e4a), fontSize: 18, fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ── 震动设置 ──
          _buildSectionCard(
            icon: Icons.vibration,
            iconColor: const Color(0xFF2395f3),
            title: '震动反馈',
            subtitle: '操作时提供触觉反馈',
            trailing: _NeuSwitch(
              value: _vibrationEnabled,
              onChanged: (v) => setState(() => _vibrationEnabled = v),
            ),
          ),
          const SizedBox(height: 14),
          // ── 陀螺仪设置 ──
          _buildSectionCard(
            icon: Icons.screen_rotation,
            iconColor: const Color(0xFF4a7c59),
            title: '陀螺仪',
            subtitle: '通过手机姿态控制摇杆',
            trailing: _NeuSwitch(
              value: _gyroEnabled,
              onChanged: (v) => setState(() => _gyroEnabled = v),
            ),
            expandChild: _gyroEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Column(
                      children: [
                        _buildSlider('X 轴灵敏度', _gyroSensX, (v) => setState(() => _gyroSensX = v)),
                        const SizedBox(height: 12),
                        _buildSlider('Y 轴灵敏度', _gyroSensY, (v) => setState(() => _gyroSensY = v)),
                      ],
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget trailing,
    Widget? expandChild,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFc4d9f0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1446a0).withValues(alpha: 0.06),
            blurRadius: 6, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(
                      color: Color(0xFF1a2e4a), fontSize: 15, fontWeight: FontWeight.w700,
                    )),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(
                      color: Color(0xFF6e8aa8), fontSize: 12,
                    )),
                  ],
                ),
              ),
              trailing,
            ],
          ),
          ...?expandChild != null ? [expandChild] : null,
        ],
      ),
    );
  }

  Widget _buildSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(
            color: Color(0xFF6e8aa8), fontSize: 12, fontWeight: FontWeight.w600,
          )),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: const Color(0xFF2395f3),
              inactiveTrackColor: const Color(0xFFdde8f4),
              thumbColor: const Color(0xFF2395f3),
              overlayColor: const Color(0xFF2395f3).withValues(alpha: 0.15),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value, min: 0.1, max: 1.0, divisions: 9,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text('${(value * 100).toInt()}%', textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF1a2e4a), fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// 拟态风格拨动开关
class _NeuSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _NeuSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48, height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value ? const Color(0xFF2395f3) : const Color(0xFFdde8f4),
          boxShadow: [
            if (!value) ...[
              BoxShadow(
                color: const Color(0xFFa9bcce).withValues(alpha: 0.4),
                blurRadius: 2, offset: const Offset(1, 1),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.8),
                blurRadius: 2, offset: const Offset(-1, -1),
              ),
            ],
            if (value)
              BoxShadow(
                color: const Color(0xFF2395f3).withValues(alpha: 0.3),
                blurRadius: 6,
              ),
          ],
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22, height: 22,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 3, offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
