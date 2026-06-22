import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import '../models/protocol.dart';
import '../transport/transport.dart';
import '../transport/ws_channel.dart';

/// 连接状态
enum ConnState {
  disconnected,
  connecting,
  waitingAuth,
  waitingApproval,
  connected,
  error,
}

/// 连接管理器 — 通过传输通道抽象与桌面端通信
///
/// 当前使用 WebSocket 通道，后续可切换到 USB/BLE
class WsService extends ChangeNotifier {
  WsChannel? _transport;
  StreamSubscription? _msgSub;
  Timer? _reconnectTimer;

  // 连接信息（用于重连）
  String? _host;
  int? _port;

  // 状态
  ConnState _state = ConnState.disconnected;
  String? _errorMessage;
  String _imeStatus = 'en';
  bool _hasControl = false;
  bool _hasEverControlled = false;
  String? _approvalIp;
  bool _vigemInstalled = false;

  // Getters
  ConnState get state => _state;
  String? get errorMessage => _errorMessage;
  String get imeStatus => _imeStatus;
  bool get hasControl => _hasControl;
  bool get hasEverControlled => _hasEverControlled;
  String? get approvalIp => _approvalIp;
  bool get isConnected => _state == ConnState.connected;
  bool get vigemInstalled => _vigemInstalled;

  // =========================================================================
  // 连接管理
  // =========================================================================

  /// 连接到桌面端（当前: WebSocket 通道）
  Future<void> connect(String host, int port) async {
    _host = host;
    _port = port;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _errorMessage = null;
    _state = ConnState.connecting;
    notifyListeners();

    try {
      _transport = WsChannel();
      _transport!.onDisconnect = _onTransportDone;
      _msgSub = _transport!.onMessage.listen(_onMessage);

      await _transport!.connect(host, port);
      // 连接成功后等待服务端推送 auth_required
    } catch (e) {
      _state = ConnState.error;
      _errorMessage = '连接失败: $e';
      notifyListeners();
      _scheduleReconnect();
    }
  }

  /// 断开连接
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _hasEverControlled = false; // 主动断开不重连
    _closeTransport();
    _state = ConnState.disconnected;
    _hasControl = false;
    _approvalIp = null;
    notifyListeners();
  }

  // =========================================================================
  // 消息发送
  // =========================================================================

  /// 发送 PIN 认证 (JSON 文本帧)
  void sendPin(String pin) {
    _sendText(CAuth(pin).encode());
  }

  /// 发送设备审批响应 (JSON 文本帧)
  void sendApproval(String r) {
    _sendText(CApprovalResp(r).encode());
    _approvalIp = null;
    notifyListeners();
  }

  /// 请求检测 ViGEmBus 驱动状态 (JSON 文本帧)
  void requestVigemCheck() {
    _sendText(CVigemCheck().encode());
  }

  /// 发送控制消息 — JSON 文本帧（带 hasControl 守卫）
  void sendMessage(ClientMsg msg) {
    if (!_hasControl) return;
    _sendText(msg.encode());
  }

  /// 发送控制消息 — TLV 二进制帧（带 hasControl 守卫）
  ///
  /// 用于高频数据（手柄状态、触控板移动等）
  void sendBinaryMsg(ClientMsg msg) {
    if (!_hasControl) return;
    // 检查消息是否支持二进制编码
    if (msg is CGamepadState) {
      _sendBinary(msg.encodeTlv());
    } else if (msg is CMove) {
      _sendBinary(msg.encodeTlv());
    } else if (msg is CScroll) {
      _sendBinary(msg.encodeTlv());
    } else {
      // 不支持二进制的消息回退到 JSON
      _sendText(msg.encode());
    }
  }

  void _sendText(String data) {
    _transport?.sendText(data);
  }

  void _sendBinary(Uint8List data) {
    _transport?.sendBinary(data);
  }

  // =========================================================================
  // 消息处理
  // =========================================================================

  void _onMessage(TransportMessage msg) {
    switch (msg) {
      case TextMessage(:final data):
        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        final serverMsg = ServerMsg.fromJson(json);
        _handleServerMsg(serverMsg);

      case BinaryMessage():
        // 当前服务端下行只发 JSON 文本帧，二进制下行（震动等）后续实现
        break;
    }
  }

  void _handleServerMsg(ServerMsg msg) {
    switch (msg) {
      case SAuthRequired():
        _state = ConnState.waitingAuth;
        _errorMessage = null;
        notifyListeners();

      case SAuthFail():
        _errorMessage = '配对码错误，请重试';
        notifyListeners();

      case SCtrlOk():
        _hasControl = true;
        _hasEverControlled = true;
        _state = ConnState.connected;
        _errorMessage = null;
        notifyListeners();

      case SWait(:final reason):
        _hasControl = false;
        _approvalIp = null;
        switch (reason) {
          case 'kicked':
            _state = ConnState.disconnected;
            _errorMessage = '已被新设备接管';
          case 'rejected':
            _state = ConnState.error;
            _errorMessage = '连接被拒绝';
          case 'timeout':
            _state = ConnState.error;
            _errorMessage = '等待超时';
          case 'busy':
            _state = ConnState.error;
            _errorMessage = '已有设备正在等待';
          default:
            // null = 等待审批中
            _state = ConnState.waitingApproval;
            _errorMessage = null;
        }
        notifyListeners();

      case SApprovalReq(:final ip):
        _approvalIp = ip;
        notifyListeners();

      case SImeInit(:final status):
        _imeStatus = status.toLowerCase();
        notifyListeners();

      case SVigemStatus(:final installed):
        _vigemInstalled = installed;
        notifyListeners();

      case SUnknown():
        break;
    }
  }

  // =========================================================================
  // 连接生命周期
  // =========================================================================

  /// 传输通道断开时的回调（由 onMessage stream 关闭触发）
  void _onTransportDone() {
    final closeCode = _transport?.closeCode;
    _transport = null;
    _msgSub?.cancel();
    _msgSub = null;

    // 根据 close code 处理
    switch (closeCode) {
      case 4001: // 被新设备接管
        _hasControl = false;
        _state = ConnState.disconnected;
        _errorMessage = '已被新设备接管';
        // 不重连
        break;
      case 4002: // 拒绝/超时/忙
        _hasControl = false;
        _state = ConnState.error;
        // errorMessage 已在 wait 消息中设置
        break;
      case 4003: // 认证失败
        _state = ConnState.error;
        _errorMessage = '认证失败';
        break;
      case 1000: // 服务端正常关闭
        _hasControl = false;
        _state = ConnState.disconnected;
        _errorMessage = '服务端已停止';
        break;
      default:
        _hasControl = false;
        if (_state == ConnState.connected) {
          _state = ConnState.disconnected;
          _errorMessage = '连接已断开';
        }
        _scheduleReconnect();
        break;
    }

    notifyListeners();
  }

  void _closeTransport() {
    _msgSub?.cancel();
    _msgSub = null;
    _transport?.dispose();
    _transport = null;
  }

  // =========================================================================
  // 重连逻辑
  // =========================================================================

  void _scheduleReconnect() {
    if (!_hasEverControlled || _host == null || _port == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_state != ConnState.connected && _host != null && _port != null) {
        connect(_host!, _port!);
      }
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _closeTransport();
    super.dispose();
  }
}
