import 'dart:convert';

// ============================================================================
// ClientMsg — 发送到服务端的消息
// ====================================================================

/// 所有客户端消息的基类
sealed class ClientMsg {
  Map<String, dynamic> toJson();
  String encode() => jsonEncode(toJson());
}

/// 鼠标移动（增量值，整数像素）
class CMove extends ClientMsg {
  final int x, y;
  CMove(this.x, this.y);
  @override
  Map<String, dynamic> toJson() => {'a': 'mv', 'x': x, 'y': y};
}

/// 点击: b=1 左键, b=2 中键, b=3 右键
class CClick extends ClientMsg {
  final int b;
  CClick([this.b = 1]);
  @override
  Map<String, dynamic> toJson() => {'a': 'clk', 'b': b};
}

/// 双击
class CDblClick extends ClientMsg {
  @override
  Map<String, dynamic> toJson() => {'a': 'dbl'};
}

/// 鼠标按下（拖拽开始）
class CMouseDown extends ClientMsg {
  final int b;
  CMouseDown([this.b = 1]);
  @override
  Map<String, dynamic> toJson() => {'a': 'md', 'b': b};
}

/// 鼠标抬起（拖拽结束）
class CMouseUp extends ClientMsg {
  final int b;
  CMouseUp([this.b = 1]);
  @override
  Map<String, dynamic> toJson() => {'a': 'mu', 'b': b};
}

/// 滚动: y=垂直, x=水平
class CScroll extends ClientMsg {
  final double x, y;
  CScroll(this.x, this.y);
  @override
  Map<String, dynamic> toJson() => {'a': 'scr', 'x': x, 'y': y};
}

/// 缩放: m=log-ratio (>0 放大, <0 缩小)
class CPinchZoom extends ClientMsg {
  final double m;
  CPinchZoom(this.m);
  @override
  Map<String, dynamic> toJson() => {'a': 'pz', 'm': m};
}

/// PIN 认证
class CAuth extends ClientMsg {
  final String pin;
  CAuth(this.pin);
  @override
  Map<String, dynamic> toJson() => {'a': 'auth', 'pin': pin};
}

/// 设备审批响应: r="accept" 或 "reject"
class CApprovalResp extends ClientMsg {
  final String r;
  CApprovalResp(this.r);
  @override
  Map<String, dynamic> toJson() => {'a': 'approval_resp', 'r': r};
}

/// 按键: k="Return", "ctrl+c" 等
class CKey extends ClientMsg {
  final String k;
  CKey(this.k);
  @override
  Map<String, dynamic> toJson() => {'a': 'key', 'k': k};
}

/// 按键（按下+释放，经过 IME 拦截）
class CKeyPress extends ClientMsg {
  final String k;
  CKeyPress(this.k);
  @override
  Map<String, dynamic> toJson() => {'a': 'kp', 'k': k};
}

/// 文本输入（拼音候选上屏等）
class CTypeText extends ClientMsg {
  final String t;
  CTypeText(this.t);
  @override
  Map<String, dynamic> toJson() => {'a': 'type', 't': t};
}

/// 退格: n=连续删除次数
class CBackspace extends ClientMsg {
  final int n;
  CBackspace([this.n = 1]);
  @override
  Map<String, dynamic> toJson() => {'a': 'bs', 'n': n};
}

/// 请求物理 IME 切换键
class CImeToggle extends ClientMsg {
  @override
  Map<String, dynamic> toJson() => {'a': 'ime_toggle'};
}

/// 请求刷新 IME 状态
class CImeRefresh extends ClientMsg {
  @override
  Map<String, dynamic> toJson() => {'a': 'ime_refresh'};
}

// ============================================================================
// ServerMsg — 从服务端接收的消息
// ====================================================================

/// 所有服务端消息的基类
sealed class ServerMsg {
  static ServerMsg fromJson(Map<String, dynamic> json) {
    switch (json['a']) {
      case 'ctrl_ok':
        return SCtrlOk(proot: json['proot'] as bool?);
      case 'wait':
        return SWait(reason: json['reason'] as String?);
      case 'approval_req':
        return SApprovalReq(ip: json['ip'] as String? ?? '');
      case 'auth_required':
        return SAuthRequired();
      case 'auth_fail':
        return SAuthFail();
      case 'ime_init':
        return SImeInit(status: json['status'] as String? ?? 'EN');
      default:
        return SUnknown(json['a'] as String? ?? 'unknown');
    }
  }
}

/// 连接成功，开始控制
class SCtrlOk extends ServerMsg {
  final bool? proot;
  SCtrlOk({this.proot});
}

/// 等待（被拒绝/超时/忙/等待审批）
class SWait extends ServerMsg {
  final String? reason; // "busy" | "kicked" | "rejected" | "timeout" | null
  SWait({this.reason});
}

/// 设备审批请求（有新设备想接管）
class SApprovalReq extends ServerMsg {
  final String ip;
  SApprovalReq({required this.ip});
}

/// 需要 PIN 认证
class SAuthRequired extends ServerMsg {}

/// 认证失败
class SAuthFail extends ServerMsg {}

/// IME 初始状态
class SImeInit extends ServerMsg {
  final String status; // "EN" | "ZH"
  SImeInit({required this.status});
}

/// 未知消息类型
class SUnknown extends ServerMsg {
  final String type;
  SUnknown(this.type);
}
