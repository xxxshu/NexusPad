import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport.dart';

/// BLE 传输通道实现
///
/// 使用 flutter_blue_plus 连接桌面端 BLE GATT Server，
/// 通过 GATT Characteristics 交换 TLV 帧。
///
/// Service UUID: 4e5c0001-f2cb-4931-a20c-7b1981273948
/// TX (Notify): 4e5c0002-f2cb-4931-a20c-7b1981273948 (Server→Client)
/// RX (WriteNoRsp): 4e5c0003-f2cb-4931-a20c-7b1981273948 (Client→Server)
class BleChannel implements TransportChannel {
  // UUID 常量
  static final Guid serviceUuid = Guid("4e5c0001-f2cb-4931-a20c-7b1981273948");
  static final Guid txCharUuid = Guid("4e5c0002-f2cb-4931-a20c-7b1981273948");
  static final Guid rxCharUuid = Guid("4e5c0003-f2cb-4931-a20c-7b1981273948");

  final _controller = StreamController<TransportMessage>.broadcast();

  TransportState _state = TransportState.disconnected;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar; // Server→Client (Notify)
  BluetoothCharacteristic? _rxChar; // Client→Server (WriteNoRsp)
  StreamSubscription? _notifySub;
  int _mtu = 23; // BLE 默认 MTU

  @override
  TransportState get state => _state;

  @override
  Stream<TransportMessage> get onMessage => _controller.stream;

  @override
  int? get closeCode => null; // BLE 没有 close code

  // ─── 扫描 ────────────────────────────────────────────────

  /// 扫描包含 NexusPad Service 的 BLE 设备
  ///
  /// 返回扫描到的设备列表，超时 [timeout] 后停止。
  Future<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 5)}) async {
    // 检查蓝牙适配器状态
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      throw Exception('蓝牙未开启');
    }

    // 开始扫描，按 Service UUID 过滤
    await FlutterBluePlus.startScan(
      timeout: timeout,
      withServices: [serviceUuid],
    );

    // 收集扫描结果
    final results = <ScanResult>[];
    final sub = FlutterBluePlus.onScanResults.listen((scanResults) {
      for (final r in scanResults) {
        if (!results.any((e) => e.device.remoteId == r.device.remoteId)) {
          results.add(r);
        }
      }
    });

    // 等待扫描完成
    await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    await sub.cancel();

    return results;
  }

  // ─── 连接 ────────────────────────────────────────────────

  /// 连接到指定的 BLE 设备
  ///
  /// 流程: 连接 → 等待配对稳定 → 发现 Service → 订阅 TX Notify
  Future<void> connectDevice(BluetoothDevice device) async {
    _state = TransportState.connecting;
    _controller.add(TextMessage('{"state":"connecting"}'));

    try {
      _device = device;

      // 连接设备 (autoConnect=true 以容忍配对过程中的短暂断开)
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: true,
      );

      // 等待配对过程完成和连接稳定
      // Android BLE 配对弹窗会导致短暂断开重连
      await Future.delayed(const Duration(seconds: 2));

      // 再次检查连接状态
      final isConnected = device.isConnected;
      if (!isConnected) {
        throw Exception('蓝牙连接已断开，请重试');
      }

      // 请求更大的 MTU（非必须，失败不影响连接）
      try {
        final mtuResult = await device.requestMtu(247);
        _mtu = mtuResult;
      } catch (_) {
        _mtu = 23; // 使用默认 MTU
      }

      // 等待 MTU 协商完成
      await Future.delayed(const Duration(milliseconds: 500));

      // 发现服务
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == serviceUuid,
        orElse: () => throw Exception('未找到 NexusPad BLE 服务'),
      );

      // 查找 TX 和 RX Characteristic
      for (final char in service.characteristics) {
        if (char.uuid == txCharUuid) {
          _txChar = char;
        } else if (char.uuid == rxCharUuid) {
          _rxChar = char;
        }
      }

      if (_txChar == null || _rxChar == null) {
        throw Exception('BLE 服务特征值缺失');
      }

      // 订阅 TX Notify (Server→Client)
      await _txChar!.setNotifyValue(true);
      _notifySub = _txChar!.lastValueStream.listen((data) {
        if (data.isNotEmpty) {
          _controller.add(BinaryMessage(Uint8List.fromList(data)));
        }
      });

      // 监听连接断开事件
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && _state == TransportState.connected) {
          _state = TransportState.disconnected;
        }
      });

      _state = TransportState.connected;
    } catch (e) {
      _state = TransportState.error;
      rethrow;
    }
  }

  @override
  Future<void> connect(String host, int port) async {
    // BLE 连接不使用 host/port，使用 connectDevice 代替
    throw UnsupportedError('BLE 连接请使用 connectDevice() 或 scanAndConnect()');
  }

  /// 扫描并连接第一个找到的 NexusPad 设备
  Future<void> scanAndConnect({Duration scanTimeout = const Duration(seconds: 5)}) async {
    final results = await scan(timeout: scanTimeout);
    if (results.isEmpty) {
      throw Exception('未发现 NexusPad 设备');
    }
    await connectDevice(results.first.device);
  }

  // ─── 数据发送 ────────────────────────────────────────────

  @override
  void sendText(String data) {
    sendBinary(Uint8List.fromList(data.codeUnits));
  }

  @override
  void sendBinary(Uint8List data) {
    if (_state != TransportState.connected || _rxChar == null) return;

    // BLE MTU 限制：每个 GATT 写入最大 payload = MTU - 3
    // 需要分片发送
    final maxPayload = _mtu - 3;
    if (maxPayload <= 0) return;

    if (data.length <= maxPayload) {
      // 单包发送
      _rxChar!.write(data, withoutResponse: true);
    } else {
      // 分片发送
      int offset = 0;
      while (offset < data.length) {
        final end = (offset + maxPayload).clamp(0, data.length);
        final chunk = data.sublist(offset, end);
        _rxChar!.write(chunk, withoutResponse: true);
        offset = end;
      }
    }
  }

  // ─── 断开连接 ────────────────────────────────────────────

  @override
  void disconnect() {
    _notifySub?.cancel();
    _notifySub = null;
    _txChar = null;
    _rxChar = null;
    _device?.disconnect();
    _device = null;
    _state = TransportState.disconnected;
  }

  @override
  void dispose() {
    disconnect();
    _controller.close();
  }

  // ─── 工具方法 ────────────────────────────────────────────

  /// 获取当前 MTU
  int get mtu => _mtu;

  /// 获取已连接的设备
  BluetoothDevice? get device => _device;

  /// 检查蓝牙是否可用
  static Future<bool> isAvailable() async {
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return false;
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  /// 检查蓝牙权限状态
  static Future<bool> checkPermissions() async {
    try {
      // flutter_blue_plus 会自动处理权限请求
      // 这里只是检查适配器状态
      final adapterState = await FlutterBluePlus.adapterState.first;
      return adapterState == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }
}
