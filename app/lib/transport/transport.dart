import 'dart:typed_data';

/// 传输通道状态
enum TransportState {
  disconnected,
  connecting,
  connected,
  error,
}

/// 传输通道接收到的消息
sealed class TransportMessage {}

/// 文本帧 (JSON)
class TextMessage extends TransportMessage {
  final String data;
  TextMessage(this.data);
}

/// 二进制帧 (TLV)
class BinaryMessage extends TransportMessage {
  final Uint8List data;
  BinaryMessage(this.data);
}

/// 传输通道抽象接口
///
/// 实现: [WsChannel] (WebSocket), 后续: UsbChannel, BleChannel
///
/// 职责: 纯粹的收发管道，不处理认证/重连/审批
abstract class TransportChannel {
  TransportState get state;
  Stream<TransportMessage> get onMessage;

  /// 连接 (host, port 由具体实现解释)
  Future<void> connect(String host, int port);

  /// 断开连接
  void disconnect();

  /// 发送文本帧 (JSON)
  void sendText(String data);

  /// 发送二进制帧 (TLV)
  void sendBinary(Uint8List data);

  /// WebSocket close code (仅 WebSocket 通道有效)
  int? get closeCode;

  /// 释放资源
  void dispose();
}
