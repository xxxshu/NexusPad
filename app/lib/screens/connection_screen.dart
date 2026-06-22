import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/ws_service.dart';
import '../transport/ble_channel.dart';
import '../transport/usb_channel.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

/// 连接服务端页（竖屏）—— 新的入口页面
/// 底部滑块切换：局域网连接 / USB连接 / 蓝牙连接
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  int _tabIndex = 0; // 0=局域网, 1=USB, 2=蓝牙
  final WsService _wsService = WsService();
  bool _connecting = false;
  String? _error;
  bool _handled = false;
  bool _navigating = false;
  bool _cameraFailed = false;
  final MobileScannerController _cameraController = MobileScannerController();

  // USB 相关状态
  final UsbChannel _usbChannel = UsbChannel();
  bool _usbConnecting = false;
  String? _usbError;
  Map<String, dynamic>? _usbAccessory;

  // BLE 相关状态
  final BleChannel _bleChannel = BleChannel();
  bool _bleScanning = false;
  bool _bleConnecting = false;
  String? _bleError;
  List<ScanResult> _bleDevices = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _wsService.addListener(_onWsChange);
  }

  @override
  void dispose() {
    _wsService.removeListener(_onWsChange);
    _usbChannel.dispose();
    _bleChannel.dispose();
    _cameraController.dispose();
    if (!_navigating) _wsService.dispose();
    super.dispose();
  }

  void _onWsChange() {
    if (!mounted) return;
    switch (_wsService.state) {
      case ConnState.waitingAuth:
        // 连接成功，进入认证页
        _navigating = true;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AuthScreen(wsService: _wsService),
          ),
        ).then((_) {
          // AuthScreen pop 回来（用户取消认证）
          if (mounted) {
            _navigating = false;
            _handled = false;
          }
        });
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
      setState(() { _connecting = true; _error = null; });
      _wsService.connect(parsed.$1, parsed.$2);
      break;
    }
  }

  (String, int)? _parseUrl(String text) {
    try {
      final uri = Uri.parse(text);
      if (uri.host.isNotEmpty && uri.port > 0) return (uri.host, uri.port);
    } catch (_) {}
    final parts = text.split(':');
    if (parts.length == 2) {
      final port = int.tryParse(parts[1]);
      if (port != null && port > 0 && port < 65536) return (parts[0], port);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFeef4fd),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            // Logo
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF003472).withValues(alpha: 0.2),
                    blurRadius: 16, offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset('assets/icon.png', width: 64, height: 64),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'NexusPad',
              style: TextStyle(
                color: Color(0xFF003472), fontSize: 22,
                fontWeight: FontWeight.w800, letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '连接到桌面端',
              style: TextStyle(color: Color(0xFF6e8aa8), fontSize: 13),
            ),
            const SizedBox(height: 32),
            // 连接方式滑块
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _buildTabBar(),
            ),
            const SizedBox(height: 20),
            // 连接内容区
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _buildLanTab(),
                    _buildUsbTab(),
                    _buildBleTab(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 顶部滑块（支持点击 + 拖拽）────────────────────────────────
  Widget _buildTabBar() {
    const labels = ['局域网', 'USB', '蓝牙'];
    const icons = [Icons.wifi, Icons.usb, Icons.bluetooth];
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabW = constraints.maxWidth / 3;
        return GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200 && _tabIndex > 0) setState(() => _tabIndex--);
            if (v > 200 && _tabIndex < 2) setState(() => _tabIndex++);
          },
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFdde8f4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              children: [
                // 滑动的白色药丸
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  left: _tabIndex * tabW + 2,
                  top: 2,
                  width: tabW - 4,
                  height: 38,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [BoxShadow(
                        color: const Color(0xFF1446a0).withValues(alpha: 0.08),
                        blurRadius: 4, offset: const Offset(0, 1),
                      )],
                    ),
                  ),
                ),
                // 三个可点击区域 + 文字（垂直居中）
                Row(
                  children: List.generate(3, (i) {
                    final selected = _tabIndex == i;
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _tabIndex = i),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icons[i], size: 15,
                                color: selected ? const Color(0xFF2395f3) : const Color(0xFF8ea8c8)),
                              const SizedBox(width: 5),
                              Text(labels[i], style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                color: selected ? const Color(0xFF1a2e4a) : const Color(0xFF8ea8c8),
                              )),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── 局域网连接 Tab ──────────────────────────────────────────
  Widget _buildLanTab() {
    return Column(
      children: [
        // QR 扫码区 — 外层圆角正方矩形
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _cameraFailed
                ? _buildCameraError()
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _cameraController,
                        onDetect: _onDetect,
                      ),
                      // 蓝色扫码框 — 正方形
                      Center(
                        child: Container(
                          width: 220, height: 220,
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0x882395f3), width: 2.5),
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      if (_connecting)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Color(0xFFe53935), fontSize: 12)),
        ],
        const SizedBox(height: 14),
        // 手动输入
        SizedBox(
          width: double.infinity, height: 44,
          child: OutlinedButton.icon(
            onPressed: _showManualEntry,
            icon: const Icon(Icons.keyboard, size: 18),
            label: const Text('手动输入 IP 地址'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2395f3),
              side: const BorderSide(color: Color(0xFFc4d9f0)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildCameraError() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFdde8f4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 48, color: Color(0xFF8ea8c8)),
            const SizedBox(height: 12),
            const Text('无法访问摄像头', style: TextStyle(
              color: Color(0xFF6e8aa8), fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('请检查摄像头权限，或使用手动输入', style: TextStyle(
              color: Color(0xFF8ea8c8), fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showManualEntry,
              icon: const Icon(Icons.keyboard, size: 18),
              label: const Text('手动输入 IP 地址'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2395f3), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── USB 连接 Tab ──────────────────────────────────────────
  Widget _buildUsbTab() {
    return Column(
      children: [
        // USB 扫描区域（与摄像头区相同大小）
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFdde8f4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_usbConnecting) ...[
                    const SizedBox(
                      width: 48, height: 48,
                      child: CircularProgressIndicator(
                        color: Color(0xFF2395f3), strokeWidth: 3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('正在连接...', style: TextStyle(
                      color: Color(0xFF6e8aa8), fontSize: 14, fontWeight: FontWeight.w600)),
                  ] else if (_usbAccessory != null) ...[
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2395f3).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.usb, size: 32, color: Color(0xFF2395f3)),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${_usbAccessory!['manufacturer'] ?? '未知'} ${_usbAccessory!['model'] ?? ''}',
                      style: const TextStyle(
                        color: Color(0xFF1a2e4a), fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    const Text('USB 配件已检测到', style: TextStyle(
                      color: Color(0xFF4a7c59), fontSize: 12)),
                  ] else ...[
                    Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFFdde8f4),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.usb, size: 32, color: Color(0xFF8ea8c8)),
                    ),
                    const SizedBox(height: 14),
                    const Text('请用 USB 线连接手机和电脑', style: TextStyle(
                      color: Color(0xFF6e8aa8), fontSize: 13)),
                    const SizedBox(height: 4),
                    const Text('插入后会自动检测', style: TextStyle(
                      color: Color(0xFF8ea8c8), fontSize: 12)),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (_usbError != null) ...[
          const SizedBox(height: 10),
          Text(_usbError!, style: const TextStyle(color: Color(0xFFe53935), fontSize: 12)),
        ],
        const SizedBox(height: 14),
        // 检测/连接按钮
        SizedBox(
          width: double.infinity, height: 44,
          child: ElevatedButton.icon(
            onPressed: _usbConnecting ? null : _connectUsb,
            icon: Icon(_usbAccessory != null ? Icons.check_circle : Icons.usb, size: 18),
            label: Text(_usbAccessory != null ? '连接' : '检测 USB 设备'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2395f3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Future<void> _connectUsb() async {
    setState(() { _usbConnecting = true; _usbError = null; });

    try {
      // 1. 检测 AOA 设备
      final accessory = await _usbChannel.getAccessory();
      if (accessory == null) {
        setState(() {
          _usbConnecting = false;
          _usbError = '未检测到 USB 配件。请确认已用 USB 线连接且桌面端已启动。';
        });
        return;
      }
      setState(() { _usbAccessory = accessory; });

      // 2. 请求权限 + 打开
      final connected = await _usbChannel.connectUsb();
      if (!connected) {
        setState(() {
          _usbConnecting = false;
          _usbError = 'USB 连接失败，请检查权限或重新插拔。';
        });
        return;
      }

      // 3. USB 免认证，直接进入 HomeScreen
      if (mounted) {
        setState(() { _usbConnecting = false; });
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HomeScreen(wsService: _wsService),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _usbConnecting = false;
          _usbError = 'USB 连接异常: $e';
        });
      }
    }
  }

  // ─── 蓝牙连接 Tab ──────────────────────────────────────────
  Widget _buildBleTab() {
    return Column(
      children: [
        // BLE 设备列表区（与摄像头区相同大小）
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFdde8f4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _bleScanning
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 48, height: 48,
                          child: CircularProgressIndicator(
                            color: Color(0xFF2395f3), strokeWidth: 3,
                          ),
                        ),
                        SizedBox(height: 16),
                        Text('正在扫描附近的设备...', style: TextStyle(
                          color: Color(0xFF6e8aa8), fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                : _bleDevices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64, height: 64,
                              decoration: BoxDecoration(
                                color: const Color(0xFFdde8f4),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.bluetooth_searching, size: 32, color: Color(0xFF8ea8c8)),
                            ),
                            const SizedBox(height: 14),
                            const Text('点击下方按钮扫描', style: TextStyle(
                              color: Color(0xFF6e8aa8), fontSize: 13)),
                            const SizedBox(height: 4),
                            const Text('确保桌面端蓝牙已开启', style: TextStyle(
                              color: Color(0xFF8ea8c8), fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _bleDevices.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final r = _bleDevices[i];
                          final name = r.advertisementData.advName.isNotEmpty
                              ? r.advertisementData.advName
                              : r.device.platformName.isNotEmpty
                                  ? r.device.platformName
                                  : r.device.remoteId.str;
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: _bleConnecting ? null : () => _connectBle(r.device),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40, height: 40,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2395f3).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.bluetooth, size: 20, color: Color(0xFF2395f3)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: const TextStyle(
                                            color: Color(0xFF1a2e4a), fontSize: 14, fontWeight: FontWeight.w600)),
                                          Text(
                                            'RSSI: ${r.rssi} dBm',
                                            style: const TextStyle(color: Color(0xFF8ea8c8), fontSize: 11),
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
                        },
                      ),
          ),
        ),
        if (_bleError != null) ...[
          const SizedBox(height: 10),
          Text(_bleError!, style: const TextStyle(color: Color(0xFFe53935), fontSize: 12)),
        ],
        const SizedBox(height: 14),
        // 扫描/连接按钮
        SizedBox(
          width: double.infinity, height: 44,
          child: ElevatedButton.icon(
            onPressed: (_bleScanning || _bleConnecting) ? null : _startBleScan,
            icon: Icon(_bleConnecting ? Icons.bluetooth_connected : Icons.bluetooth_searching, size: 18),
            label: Text(_bleConnecting ? '连接中...' : _bleScanning ? '扫描中...' : '扫描蓝牙设备'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2395f3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Future<void> _startBleScan() async {
    // 检查蓝牙权限
    final available = await BleChannel.isAvailable();
    if (!available) {
      setState(() {
        _bleError = '请开启蓝牙后再试';
      });
      return;
    }

    setState(() {
      _bleScanning = true;
      _bleError = null;
      _bleDevices = [];
    });

    try {
      final devices = await _bleChannel.scan(timeout: const Duration(seconds: 6));
      if (mounted) {
        setState(() {
          _bleScanning = false;
          _bleDevices = devices;
          if (devices.isEmpty) {
            _bleError = '未发现 NexusPad 设备，请确认桌面端蓝牙已开启';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bleScanning = false;
          _bleError = '扫描失败: $e';
        });
      }
    }
  }

  Future<void> _connectBle(BluetoothDevice device) async {
    setState(() {
      _bleConnecting = true;
      _bleError = null;
    });

    try {
      await _bleChannel.connectDevice(device);

      // BLE 免认证，直接进入 HomeScreen
      if (mounted) {
        setState(() { _bleConnecting = false; });
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => HomeScreen(wsService: _wsService),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _bleConnecting = false;
          _bleError = '蓝牙连接失败: $e';
        });
      }
    }
  }

  // ─── 手动输入 ────────────────────────────────────────────────
  void _showManualEntry() {
    final ipCtrl = TextEditingController();
    final portCtrl = TextEditingController(text: '8765');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动连接'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: ipCtrl, decoration: const InputDecoration(
              labelText: 'IP 地址', hintText: '192.168.1.100',
            )),
            const SizedBox(height: 12),
            TextField(controller: portCtrl, decoration: const InputDecoration(
              labelText: '端口', hintText: '8765',
            ), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final port = int.tryParse(portCtrl.text) ?? 8765;
              Navigator.pop(ctx);
              setState(() { _connecting = true; _error = null; _handled = true; });
              _wsService.connect(ipCtrl.text.trim(), port);
            },
            child: const Text('连接'),
          ),
        ],
      ),
    );
  }
}
