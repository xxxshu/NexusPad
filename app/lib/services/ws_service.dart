import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/protocol.dart';

/// 连接状态
enum ConnState {
  disconnected,
  connecting,
  waitingAuth,
  waitingApproval,
  connected,
  error,
}

/// WebSocket 连接管理器
class WsService extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
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

  // Getters
  ConnState get state => _state;
  String? get errorMessage => _errorMessage;
  String get imeStatus => _imeStatus;
  bool get hasControl => _hasControl;
  bool get hasEverControlled => _hasEverControlled;
  String? get approvalIp => _approvalIp;
  bool get isConnected => _state == ConnState.connected;

  // =========================================================================
  // 连接管理
  // =========================================================================

  /// 连接到桌面端 WebSocket 服务
  Future<void> connect(String host, int port) async {
    _host = host;
    _port = port;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _errorMessage = null;
    _state = ConnState.connecting;
    notifyListeners();

    try {
      final uri = Uri.parse('ws://$host:$port/ws');
      _channel = WebSocketChannel.connect(uri);

      // 等待连接建立
      await _channel!.ready;

      _sub = _channel!.stream.listen(
        _onData,
        onDone: _onDone,
        onError: _onError,
      );
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
    _closeChannel();
    _state = ConnState.disconnected;
    _hasControl = false;
    _approvalIp = null;
    notifyListeners();
  }

  // =========================================================================
  // 消息发送
  // =========================================================================

  /// 发送 PIN 认证
  void sendPin(String pin) {
    _sendRaw(CAuth(pin).encode());
  }

  /// 发送设备审批响应
  void sendApproval(String r) {
    _sendRaw(CApprovalResp(r).encode());
    _approvalIp = null;
    notifyListeners();
  }

  /// 发送控制消息（带 hasControl 守卫）
  void sendMessage(ClientMsg msg) {
    if (!_hasControl) return;
    _sendRaw(msg.encode());
  }

  void _sendRaw(String data) {
    if (_channel != null) {
      try {
        _channel!.sink.add(data);
      } catch (_) {
        // 发送失败，连接可能已断开
      }
    }
  }

  // =========================================================================
  // 消息处理
  // =========================================================================

  void _onData(dynamic data) {
    if (data is! String) return;

    Map<String, dynamic> json;
    try {
      json = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final msg = ServerMsg.fromJson(json);
    _handleServerMsg(msg);
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

      case SUnknown():
        break;
    }
  }

  // =========================================================================
  // 连接生命周期
  // =========================================================================

  void _onDone() {
    final closeCode = _channel?.closeCode;
    _channel = null;
    _sub?.cancel();
    _sub = null;

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

  void _onError(Object error) {
    _channel?.sink.close();
  }

  void _closeChannel() {
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
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
    _closeChannel();
    super.dispose();
  }
}
