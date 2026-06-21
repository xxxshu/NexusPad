import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 自定义手柄布局数据模型
class GamepadLayout {
  String id;
  String name;
  String createdAt;
  List<LayoutElement> elements;

  GamepadLayout({
    required this.id,
    required this.name,
    required this.createdAt,
    List<LayoutElement>? elements,
  }) : elements = elements ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'elements': elements.map((e) => e.toJson()).toList(),
  };

  factory GamepadLayout.fromJson(Map<String, dynamic> json) => GamepadLayout(
    id: json['id'] as String,
    name: json['name'] as String,
    createdAt: json['createdAt'] as String,
    elements: (json['elements'] as List?)
        ?.map((e) => LayoutElement.fromJson(e as Map<String, dynamic>))
        .toList() ?? [],
  );

  GamepadLayout copy() => GamepadLayout.fromJson(toJson());
}

/// 布局中的单个元素
class LayoutElement {
  String type;      // "button" | "joystick" | "touchpad"
  double x, y;      // 位置 (屏幕比例 0.0~1.0，左上角为原点)
  double size;      // 大小 (屏幕短边比例)

  // button 专用
  String? buttonId; // "a","b","x","y","lb","rb","lt","rt","up","down","left","right","ls","rs","back","menu","guide"
  String? label;    // 显示文字

  // joystick 专用
  String? stickSide; // "left" | "right"

  // touchpad 专用
  String? mapTo;       // "left" | "right" (映射到哪个摇杆)
  double? sensitivity; // 灵敏度

  LayoutElement({
    required this.type,
    required this.x,
    required this.y,
    required this.size,
    this.buttonId,
    this.label,
    this.stickSide,
    this.mapTo,
    this.sensitivity,
  });

  Map<String, dynamic> toJson() => {
    'type': type,
    'x': x,
    'y': y,
    'size': size,
    if (buttonId != null) 'buttonId': buttonId,
    if (label != null) 'label': label,
    if (stickSide != null) 'stickSide': stickSide,
    if (mapTo != null) 'mapTo': mapTo,
    if (sensitivity != null) 'sensitivity': sensitivity,
  };

  factory LayoutElement.fromJson(Map<String, dynamic> json) => LayoutElement(
    type: json['type'] as String,
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    size: (json['size'] as num).toDouble(),
    buttonId: json['buttonId'] as String?,
    label: json['label'] as String?,
    stickSide: json['stickSide'] as String?,
    mapTo: json['mapTo'] as String?,
    sensitivity: (json['sensitivity'] as num?)?.toDouble(),
  );
}

/// 自定义布局持久化管理
class LayoutStorage {
  static const _key = 'custom_gamepad_layouts';

  static Future<List<GamepadLayout>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return list
          .map((e) => GamepadLayout.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveAll(List<GamepadLayout> layouts) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(layouts.map((l) => l.toJson()).toList());
    await prefs.setString(_key, json);
  }

  static Future<void> save(GamepadLayout layout) async {
    final layouts = await loadAll();
    final idx = layouts.indexWhere((l) => l.id == layout.id);
    if (idx >= 0) {
      layouts[idx] = layout;
    } else {
      layouts.add(layout);
    }
    await saveAll(layouts);
  }

  static Future<void> delete(String id) async {
    final layouts = await loadAll();
    layouts.removeWhere((l) => l.id == id);
    await saveAll(layouts);
  }
}
