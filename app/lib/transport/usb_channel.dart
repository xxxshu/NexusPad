import 'dart:async';

import 'package:flutter/services.dart';

import 'transport.dart';

/// USB AOA 传输通道实现
///
/// 通过 MethodChannel 与 Android 原生 UsbHostPlugin 通信
class UsbChannel implements TransportChannel {
  static const _methodChannel = MethodChannel('com.nexuspad.usb');
  static const _eventChannel = EventChannel('com.nexuspad.usb/stream');

  final _controller = StreamController<TransportMessage>.broadcast();
  StreamSubscription? _eventSub;

  TransportState _state = TransportState.disconnected;

  @override
  TransportState get state => _state;

  @override
  Stream<TransportMessage> get onMessage => _controller.stream;

  @override
  int? get closeCode => null; // USB 没有 close code 概念

  @override
  Future<void> connect(String host, int port) async {
    // USB 连接不需要 host/port，参数被忽略
    // 连接流程由外部（ConnectionScreen）通过专用方法控制
  }

  /// 检查是否有 AOA 设备连接
  Future<Map<String, dynamic>?> getAccessory() async {
    try {
      final result = await _methodChannel.invokeMethod('getAccessory');
      return result as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  /// 请求 USB 权限
  Future<bool> requestPermission() async {
    try {
      final result = await _methodChannel.invokeMethod('requestPermission');
      return result == true;
    } catch (e) {
      return false;
    }
  }

  /// 打开 AOA Accessory 并建立读写流
  ///
  /// 成功后自动开始监听 EventChannel 数据
  Future<bool> openAccessory() async {
    try {
      final result = await _methodChannel.invokeMethod('openAccessory');
      if (result == true) {
        _state = TransportState.connected;
        _startListening();
        return true;
      }
      _state = TransportState.error;
      return false;
    } catch (e) {
      _state = TransportState.error;
      return false;
    }
  }

  /// 完整的 USB 连接流程：检测 → 权限 → 打开
  Future<bool> connectUsb() async {
    _state = TransportState.connecting;

    // 1. 检测 AOA 设备
    final accessory = await getAccessory();
    if (accessory == null) {
      _state = TransportState.error;
      return false;
    }

    // 2. 请求权限
    final granted = await requestPermission();
    if (!granted) {
      _state = TransportState.error;
      return false;
    }

    // 3. 打开 Accessory
    return openAccessory();
  }

  void _startListening() {
    _eventSub?.cancel();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Uint8List) {
          _controller.add(BinaryMessage(data));
        } else if (data is List) {
          _controller.add(BinaryMessage(Uint8List.fromList(data.cast<int>())));
        }
      },
      onError: (error) {
        _state = TransportState.error;
      },
      onDone: () {
        _state = TransportState.disconnected;
      },
    );
  }

  @override
  void disconnect() {
    _eventSub?.cancel();
    _eventSub = null;
    _state = TransportState.disconnected;
    try {
      _methodChannel.invokeMethod('close');
    } catch (_) {}
  }

  @override
  void sendText(String data) {
    // USB 通道不直接发送文本，所有数据通过 sendBinary 以 TLV 帧发送
    // 如果需要发送 JSON，应先包装成 TLV 帧再发送
    _methodChannel.invokeMethod('writeData', Uint8List.fromList(data.codeUnits));
  }

  @override
  void sendBinary(Uint8List data) {
    if (_state == TransportState.connected) {
      try {
        _methodChannel.invokeMethod('writeData', data);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _eventSub = null;
    _controller.close();
    try {
      _methodChannel.invokeMethod('close');
    } catch (_) {}
  }
}
