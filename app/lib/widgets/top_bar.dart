import 'package:flutter/material.dart';

import '../services/ws_service.dart';

/// 顶部工具栏
class TopBar extends StatelessWidget {
  final WsService wsService;

  const TopBar({super.key, required this.wsService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wsService,
      builder: (context, _) {
        final connected = wsService.isConnected;
        final imeStatus = wsService.imeStatus;

        return Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
          ),
          child: Row(
            children: [
              // 连接状态指示灯
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected ? const Color(0xFF34a853) : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                connected ? '已连接' : '已断开',
                style: TextStyle(
                  color: connected
                      ? const Color(0xFF34a853)
                      : Colors.red,
                  fontSize: 12,
                ),
              ),

              const Spacer(),

              // IME 状态
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  imeStatus == 'zh' ? '中' : 'EN',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Fn 按钮（Phase 2 占位）
              IconButton(
                onPressed: null, // Phase 2 实现
                icon: Icon(
                  Icons.functions,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
                tooltip: '功能键面板',
              ),

              // 键盘按钮（Phase 2 占位）
              IconButton(
                onPressed: null, // Phase 2 实现
                icon: Icon(
                  Icons.keyboard,
                  color: Colors.white.withValues(alpha: 0.3),
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
                tooltip: '键盘',
              ),
            ],
          ),
        );
      },
    );
  }
}
