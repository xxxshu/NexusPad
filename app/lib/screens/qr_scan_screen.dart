import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  bool _handled = false;
  bool _navigating = false;
  bool _cameraFailed = false;
  final MobileScannerController _cameraController = MobileScannerController();

  @override
  void initState() {
    super.initState();
    _wsService.addListener(_onWsChange);
  }

  void _onWsChange() {
    if (!mounted) return;
    switch (_wsService.state) {
      case ConnState.waitingAuth:
        break;
      case ConnState.error:
        setState(() {
          _connecting = false;
          _error = _wsService.errorMessage;
          _handled = false;
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
      break;
    }
  }

  (String, int)? _parseUrl(String text) {
    try {
      final uri = Uri.parse(text.trim());
      final host = uri.host;
      final port = uri.port;
      if (host.isNotEmpty && port > 0 && port < 65536) {
        return (host, port);
      }
    } catch (_) {}
    // 尝试直接解析 "ip:port" 格式
    final parts = text.trim().split(':');
    if (parts.length == 2) {
      final host = parts[0];
      final port = int.tryParse(parts[1]);
      if (host.isNotEmpty && port != null && port > 0 && port < 65536) {
        return (host, port);
      }
    }
    return null;
  }

  void _showManualInput() {
    final hostController = TextEditingController();
    final portController = TextEditingController(text: '8765');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动连接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostController,
              decoration: const InputDecoration(
                labelText: 'IP 地址',
                hintText: '192.168.1.100',
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '8765',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final host = hostController.text.trim();
              final port = int.tryParse(portController.text.trim());
              if (host.isEmpty || port == null) return;
              Navigator.of(ctx).pop();
              setState(() {
                _connecting = true;
                _error = null;
                _handled = true;
              });
              _wsService.connect(host, port).then((_) {
                if (!mounted) return;
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
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
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
          // 相机预览（带错误处理）
          if (!_cameraFailed)
            MobileScanner(
              controller: _cameraController,
              onDetect: _onDetect,
              errorBuilder: (context, error) {
                // 相机初始化失败，显示手动输入
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_cameraFailed) {
                    setState(() => _cameraFailed = true);
                  }
                });
                return _buildManualEntry();
              },
            )
          else
            _buildManualEntry(),

          // 扫描框覆盖层（仅相机正常时显示）
          if (!_cameraFailed)
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
                else if (!_cameraFailed)
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

  Widget _buildManualEntry() {
    return Container(
      color: const Color(0xFF0f1a2e),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.camera_alt_outlined,
              color: Color(0xFF6e8aa8),
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text(
              '相机不可用',
              style: TextStyle(color: Color(0xFF8ab4e0), fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '请使用手动输入连接桌面端',
              style: TextStyle(color: Color(0xFF6e8aa8), fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showManualInput,
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('手动输入 IP', style: TextStyle(fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2395f3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                setState(() {
                  _cameraFailed = false;
                  _handled = false;
                });
              },
              child: const Text('重试相机', style: TextStyle(color: Color(0xFF2395f3))),
            ),
          ],
        ),
      ),
    );
  }
}
