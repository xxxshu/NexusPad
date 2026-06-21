import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/control_mode.dart';
import '../services/ws_service.dart';
import 'auth_screen.dart';

/// QR 码扫描页
class QRScanScreen extends StatefulWidget {
  final ControlMode mode;
  const QRScanScreen({super.key, required this.mode});

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  final WsService _wsService = WsService();
  bool _connecting = false;
  String? _error;
  bool _handled = false; // 防止重复处理
  bool _navigating = false; // 正在导航到认证页，不dispose

  @override
  void initState() {
    super.initState();
    // 监听连接状态
    _wsService.addListener(_onWsChange);
  }

  void _onWsChange() {
    if (!mounted) return;
    switch (_wsService.state) {
      case ConnState.waitingAuth:
        // 认证页面由 _onDetect 处理导航
        break;
      case ConnState.error:
        setState(() {
          _connecting = false;
          _error = _wsService.errorMessage;
          _handled = false; // 允许重试
        });
        break;
      default:
        break;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final parsed = _parseUrl(raw);
      if (parsed == null) continue;

      _handled = true;
      setState(() {
        _connecting = true;
        _error = null;
      });

      _wsService.connect(parsed.$1, parsed.$2).then((_) {
        if (!mounted) return;
        // 连接成功后等待 auth_required 消息
        // 用延迟检查：如果 500ms 内收到 auth_required，导航到认证页
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          if (_wsService.state == ConnState.waitingAuth) {
            _navigating = true;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => AuthScreen(wsService: _wsService, mode: widget.mode),
              ),
            );
          }
        });
      });
      break; // 只处理第一个有效码
    }
  }

  /// 解析 URL：http://ip:port → (host, port)
  (String, int)? _parseUrl(String text) {
    try {
      final uri = Uri.parse(text.trim());
      final host = uri.host;
      final port = uri.port;
      if (host.isNotEmpty && port > 0 && port < 65536) {
        return (host, port);
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _wsService.removeListener(_onWsChange);
    if (!_navigating && !_wsService.isConnected) {
      _wsService.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 相机预览
          MobileScanner(
            onDetect: _onDetect,
          ),

          // 扫描框覆盖层
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _connecting
                      ? Colors.orange
                      : const Color(0xFF2395f3),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // 底部提示
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                if (_connecting)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        '正在连接...',
                        style: TextStyle(color: Colors.orange, fontSize: 14),
                      ),
                    ],
                  )
                else if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                    textAlign: TextAlign.center,
                  )
                else
                  Text(
                    '扫描桌面端二维码连接',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),

          // 返回按钮
          Positioned(
            top: 16,
            left: 8,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
