import 'dart:typed_data';

/// TLV (Type-Length-Value) 二进制帧编解码器
///
/// 帧格式: [1B type][2B length (big-endian)][NB payload]
/// - type:   帧类型, 见 `FrameType`
/// - length: payload 长度, uint16 大端序, 最大 65535
/// - payload: 原始字节
class TlvCodec {
  static const int headerSize = 3;

  /// 编码一个 TLV 帧
  static Uint8List encode(int type, Uint8List payload) {
    final len = payload.length;
    final buf = Uint8List(headerSize + len);
    buf[0] = type & 0xFF;
    buf[1] = (len >> 8) & 0xFF;
    buf[2] = len & 0xFF;
    buf.setRange(headerSize, headerSize + len, payload);
    return buf;
  }

  /// 解码一个 TLV 帧
  ///
  /// 返回 `(type, payload, consumed)` 或 `null`（数据不足时）
  static ({int type, Uint8List payload, int consumed})? decode(
    Uint8List data, {
    int offset = 0,
  }) {
    final remaining = data.length - offset;
    if (remaining < headerSize) return null;

    final type = data[offset];
    final len = (data[offset + 1] << 8) | data[offset + 2];

    if (remaining < headerSize + len) return null;

    final payload = Uint8List.view(
      data.buffer,
      data.offsetInBytes + offset + headerSize,
      len,
    );

    return (type: type, payload: payload, consumed: headerSize + len);
  }
}
