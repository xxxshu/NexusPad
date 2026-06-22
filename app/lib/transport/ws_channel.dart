import 'dart:async';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport.dart';

/// WebSocket 传输通道实现
///
/// 包装 [WebSocketChannel]，统一文本/二进制帧接口
class WsChannel implements TransportChannel {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _controller = StreamController<TransportMessage>.broadcast();

  TransportState _state = TransportState.disconnected;
  int? _closeCode;

  /// 连接断开时的回调（用于通知上层进行状态清理和重连判断）
  void Function()? onDisconnect;

  @override
  TransportState get state => _state;

  @override
  Stream<TransportMessage> get onMessage => _controller.stream;

  @override
  int? get closeCode => _closeCode;

  @override
  Future<void> connect(String host, int port) async {
    disconnect();
    _state = TransportState.connecting;
    _closeCode = null;

    try {
      final uri = Uri.parse('ws://$host:$port/ws');
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      _state = TransportState.connected;

      _sub = _channel!.stream.listen(
        (data) {
          if (data is String) {
            _controller.add(TextMessage(data));
          } else if (data is List<int>) {
            _controller.add(BinaryMessage(Uint8List.fromList(data)));
          }
        },
        onDone: () {
          _closeCode = _channel?.closeCode;
          _state = TransportState.disconnected;
          _channel = null;
          _sub?.cancel();
          _sub = null;
          onDisconnect?.call();
        },
        onError: (error) {
          _state = TransportState.error;
          _channel?.sink.close();
        },
      );
    } catch (e) {
      _state = TransportState.error;
      rethrow;
    }
  }

  @override
  void disconnect() {
    _sub?.cancel();
    _sub = null;
    _closeCode = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _state = TransportState.disconnected;
  }

  @override
  void sendText(String data) {
    if (_channel != null && _state == TransportState.connected) {
      try {
        _channel!.sink.add(data);
      } catch (_) {}
    }
  }

  @override
  void sendBinary(Uint8List data) {
    if (_channel != null && _state == TransportState.connected) {
      try {
        _channel!.sink.add(data);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    disconnect();
    _controller.close();
  }
}
