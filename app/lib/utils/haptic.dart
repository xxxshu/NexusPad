import 'package:vibration/vibration.dart';

/// 震动反馈工具类
/// 封装 HapticFeedback 模式，与网页版 app.js 的震动模式一致
class Haptic {
  static bool? _hasVibrator;
  static bool? _hasAmplitude;

  /// 初始化震动器能力检测
  static Future<void> init() async {
    _hasVibrator = await Vibration.hasVibrator();
    _hasAmplitude = await Vibration.hasAmplitudeControl();
  }

  /// 单击震动 (15ms)
  static Future<void> tap() => _vibrate(15);

  /// 双击震动 [12, 50, 12]
  static Future<void> doubleTap() => _vibratePattern([12, 50, 12]);

  /// 长按拖拽开始 (30ms)
  static Future<void> dragStart() => _vibrate(30);

  /// 拖拽结束 (18ms)
  static Future<void> dragEnd() => _vibrate(18);

  /// 按键震动 (15ms，与触控板 tap 一致)
  static Future<void> keyPress() => _vibrate(15);

  /// 手柄按钮按下 (10ms，轻触感)
  static Future<void> buttonPress() => _vibrate(10);

  /// 摇杆到达边缘 (15ms)
  static Future<void> stickEdge() => _vibrate(15);

  /// 滚动刻度震动 (8-20ms, 按强度缩放)
  /// [intensity] 0.0 ~ 1.0
  static Future<void> scrollTick(double intensity) {
    final ms = (8 + (intensity.clamp(0.0, 1.0) * 12)).round();
    return _vibrate(ms);
  }

  /// 停止震动
  static Future<void> cancel() async {
    if (_hasVibrator == true) {
      await Vibration.cancel();
    }
  }

  /// 单次震动
  static Future<void> _vibrate(int ms) async {
    if (_hasVibrator != true) return;
    if (_hasAmplitude == true) {
      await Vibration.vibrate(duration: ms, amplitude: 255);
    } else {
      await Vibration.vibrate(duration: ms);
    }
  }

  /// 模式震动 (震动-暂停-震动...)
  static Future<void> _vibratePattern(List<int> pattern) async {
    if (_hasVibrator != true) return;
    await Vibration.vibrate(pattern: pattern);
  }
}
