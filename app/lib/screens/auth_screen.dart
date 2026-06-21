import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/control_mode.dart';
import '../services/ws_service.dart';
import 'gamepad_select_screen.dart';
import 'touchpad_screen.dart';

/// PIN 认证页
class AuthScreen extends StatefulWidget {
  final WsService wsService;
  final ControlMode mode;

  const AuthScreen({super.key, required this.wsService, required this.mode});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _pinFocus = FocusNode();
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    widget.wsService.addListener(_onWsChange);
    // 自动聚焦
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pinFocus.requestFocus();
    });
  }

  void _onWsChange() {
    if (!mounted) return;
    final ws = widget.wsService;

    switch (ws.state) {
      case ConnState.connected:
        // 认证成功，根据模式跳转不同页面
        if (widget.mode == ControlMode.gamepad) {
          // 游戏手柄模式：先检测驱动，再跳转
          ws.requestVigemCheck();
          // 等待 vigem 检测结果（最多 500ms）
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            if (ws.vigemInstalled) {
              Navigator.of(context).pushReplacement(
                PageRouteBuilder(
                  pageBuilder: (_, a, b) => GamepadSelectScreen(wsService: ws),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            } else {
              // 驱动未安装，弹窗提示并返回首页
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('缺少驱动'),
                  content: const Text('请先在电脑上安装 ViGEmBus 驱动，然后重启 NexusPad。\n\n可在设置面板中找到下载链接。'),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        ws.disconnect();
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            }
          });
        } else {
          // 触控板模式：无动画瞬间切换
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (_, a, b) => TouchpadScreen(wsService: ws),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        }
        break;
      case ConnState.waitingApproval:
        setState(() {
          _error = null;
          _submitting = false;
        });
        break;
      case ConnState.waitingAuth:
        setState(() {
          _error = ws.errorMessage; // auth_fail 消息
          _submitting = false;
        });
        if (_error != null) {
          _pinController.clear();
          _pinFocus.requestFocus();
        }
        break;
      case ConnState.error:
        setState(() {
          _error = ws.errorMessage;
          _submitting = false;
        });
        break;
      default:
        break;
    }

    // 审批请求
    if (ws.approvalIp != null && mounted) {
      _showApprovalDialog(ws.approvalIp!);
    }
  }

  void _submitPin() {
    final pin = _pinController.text.trim();
    if (pin.length < 4) {
      setState(() => _error = '请输入至少4位配对码');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    widget.wsService.sendPin(pin);
  }

  void _showApprovalDialog(String ip) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('设备审批'),
        content: Text('$ip 正在请求接管控制'),
        actions: [
          TextButton(
            onPressed: () {
              widget.wsService.sendApproval('reject');
              Navigator.of(ctx).pop();
            },
            child: const Text('拒绝', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              widget.wsService.sendApproval('accept');
              Navigator.of(ctx).pop();
            },
            child: const Text('接受', style: TextStyle(color: Color(0xFF2395f3))),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.wsService.removeListener(_onWsChange);
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ws = widget.wsService;
    final isWaiting = ws.state == ConnState.waitingApproval;

    return Scaffold(
      backgroundColor: const Color(0xFFeef4fd),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            ws.disconnect();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1a2e4a)),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 48,
                color: Color(0xFF2395f3),
              ),
              const SizedBox(height: 24),
              Text(
                isWaiting ? '等待审批...' : '输入配对码',
                style: const TextStyle(
                  color: Color(0xFF1a2e4a),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isWaiting
                    ? '当前设备正在等待审批，请在已连接的设备上确认'
                    : '请输入桌面端显示的6位配对码',
                style: const TextStyle(
                  color: Color(0xFF6e8aa8),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              if (!isWaiting) ...[
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _pinController,
                    focusNode: _pinFocus,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(
                      color: Color(0xFF2395f3),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 12,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '······',
                      hintStyle: const TextStyle(
                        color: Color(0xFFc4d9f0),
                        letterSpacing: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFc4d9f0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFF2395f3),
                          width: 2,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _submitPin(),
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: 280,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2395f3),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            '连接',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFe53935), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
