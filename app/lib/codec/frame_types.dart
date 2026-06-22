/// TLV 帧类型常量
///
/// 帧格式: [1B type][2B length (big-endian)][NB payload]
class FrameType {
  /// 控制帧 — JSON payload (认证、审批等)
  static const int control = 0x01;

  /// 输入帧 — 纯二进制 (触控板 move/scroll 等高频操作)
  static const int input = 0x02;

  /// 手柄帧 — 纯二进制 (摇杆+扳机+按钮+陀螺仪)
  static const int gamepad = 0x03;

  /// 系统帧 — JSON payload (IME、ViGEm 状态等)
  static const int system = 0x04;

  /// 心跳帧 — 无 payload
  static const int heartbeat = 0xFF;
}

/// 输入帧子类型 (payload 第一个字节)
class InputSubType {
  static const int move = 0x01;
  static const int scroll = 0x02;
}
