<div align="center">
  <img src="src-tauri/icons/icon.svg" width="96" alt="NexusPad Logo">

  # NexusPad

  **把手机变成电脑的无线触控板、键盘和游戏手柄 —— 同一局域网下，扫码即连。**

  [![Release](https://img.shields.io/github/v/release/xxxshu/NexusPad)](https://github.com/xxxshu/NexusPad/releases)
  [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](#许可证)
</div>

---

## 功能

- **触控板** — 单指移动、双指滚动/缩放、点击/双击、长按拖动，本地手势引擎即时响应
- **键盘** — 实时输入、退格、回车，内置拼音输入法与候选词
- **功能键** — Esc / Tab / Del / 方向键 / Ctrl / Shift / Alt，支持锁定修饰键组合
- **游戏手柄** — 虚拟 Xbox 手柄（Windows，基于 ViGEmBus），内置多种布局并支持自定义编辑
- **多种连接** — WiFi（扫码直连）、USB（AOA 低延迟）、BLE
- **PIN 配对** — 6 位数字配对码，每次认证后自动刷新
- **连接审批** — 已连接设备可批准/拒绝新设备接入
- **跨平台桌面端** — Windows 10/11（Linux 构建暂时搁置）

## 下载安装

前往 [Releases](https://github.com/xxxshu/NexusPad/releases) 下载最新版本：

| 端 | 平台 | 文件 |
|------|------|------|
| 桌面端 | Windows 10/11 (x64) | `NexusPad_<版本>_x64-setup.exe` |
| 手机端 | Android | `NexusPad_<版本>.apk` |

> Linux 端（`.deb`）构建暂时搁置，计划在后续版本恢复。iOS 端规划中。

## 使用方法

1. 启动桌面端，选择连接模式（默认 WiFi），设置端口（默认 8765），点击「启动」
2. 打开手机端 App 扫描二维码，或在手机浏览器输入桌面端显示的地址
3. 在手机上输入 6 位 PIN 配对码
4. 如已有设备连接，需在电脑端批准新设备
5. 开始使用

## 技术架构

```
手机端 (Flutter)                      PC 桌面端 (Tauri v2 / Rust)
┌──────────────────┐                ┌─────────────────────────────┐
│  触控板手势引擎   │   WebSocket    │  axum HTTP + WS Server      │
│  OSK 键盘 + 拼音  │ ◀── JSON ───▶ │  ├─ 鼠标/键盘模拟 (enigo)   │
│  功能键面板       │   或 TLV       │  ├─ 剪贴板 (arboard)        │
│  游戏手柄 UI     │   二进制帧     │  ├─ IME 状态管理 (平台 API)  │
│  PIN 认证        │                │  └─ 虚拟手柄 (ViGEmBus)     │
│                  │  WiFi/USB/BLE  │                             │
│  统一传输抽象     │ ◀───────────▶ │  Tauri 桌面 GUI (React)     │
│  (TransportChannel)               │   服务启停 · QR/PIN · 设置  │
└──────────────────┘                └─────────────────────────────┘
```

桌面端按所选连接模式分别拉起 WebSocket / USB(AOA) / BLE 监听器；手机端通过统一的
`TransportChannel` 接口适配三种通道。文本指令走 JSON，高频/二进制数据走 TLV 编码。

### 技术栈

| 组件 | 技术 |
|------|------|
| 桌面框架 | Tauri v2 |
| 后端语言 | Rust (tokio + axum) |
| 输入模拟 | enigo（跨平台） |
| 剪贴板 | arboard |
| 虚拟手柄 | vigem-client (ViGEmBus) |
| USB / BLE | rusb / windows WinRT |
| 二维码 | qrcode |
| 手机端 | Flutter (Dart) |
| 桌面端 UI | Vite + React + TypeScript |
| 浏览器端（备用） | 原生 HTML / CSS / JS |

## 从源码构建

### 前置条件

- [Node.js](https://nodejs.org/) 18+
- [Rust](https://rustup.rs/) 1.70+ 与 [Tauri CLI v2](https://tauri.app/start/prerequisites/)（`cargo install tauri-cli --version "^2"`）
- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.x（构建手机端）

### 桌面端（Windows）

```bash
git clone https://github.com/xxxshu/NexusPad.git
cd NexusPad

# 安装桌面 UI 依赖
cd src-tauri/ui && npm install && cd ../..

# 开发模式
cargo tauri dev

# 打包发布（产物位于 src-tauri/target/release/bundle/）
cargo tauri build
```

### 手机端（Android）

```bash
cd app
flutter pub get
flutter build apk --release   # 产物: build/app/outputs/flutter-apk/app-release.apk
```

## 项目结构

```
NexusPad/
├── app/                     # 手机端 (Flutter)
│   └── lib/
│       ├── main.dart
│       ├── screens/         # 连接 / 扫码 / 认证 / 触控板 / 手柄 / 设置
│       ├── transport/       # 传输抽象: WebSocket / USB / BLE
│       ├── codec/           # TLV 二进制编解码
│       ├── utils/           # 手势引擎 · 震动反馈
│       ├── models/          # 控制模式 · 手柄布局 · 协议
│       └── widgets/         # 手柄控件 · 顶栏
│
├── frontend/                # 浏览器备用前端 (原生 HTML/JS + 拼音词库)
│
├── src-tauri/               # PC 桌面端 (Rust + Tauri v2)
│   ├── src/
│   │   ├── main.rs / lib.rs # 入口 + Tauri 命令 + 系统托盘
│   │   ├── server.rs        # HTTP + WebSocket 服务，PIN 认证状态机
│   │   ├── input.rs         # 跨平台鼠标/键盘/滚动模拟
│   │   ├── protocol.rs      # 消息协议
│   │   ├── codec.rs         # TLV 编解码
│   │   ├── gamepad.rs       # ViGEmBus 虚拟手柄
│   │   ├── usb.rs / debug_usb.rs   # USB AOA 连接 + 驱动诊断
│   │   ├── ble.rs           # BLE GATT 服务端
│   │   ├── config.rs        # 配置持久化
│   │   └── platform/        # Win/Mac/Linux IME 状态读取与切换
│   └── ui/                  # 桌面管理界面 (Vite + React + TS)
│
└── .github/workflows/       # CI: 多平台构建（当前手动触发）
```

## WebSocket 消息协议

**客户端 → 服务端：**

| 动作 | 字段 | 说明 |
|------|------|------|
| `mv` | `x, y` | 鼠标移动（增量像素） |
| `clk` | `b` | 单击（0 左 / 1 中 / 2 右） |
| `dbl` | — | 双击 |
| `md` / `mu` | `b` | 鼠标按下 / 释放（拖拽） |
| `scr` | `y, x` | 滚动 |
| `pz` | `m` | 缩放 |
| `type` | `t` | 输入文字 |
| `key` / `kp` | `k` | 按键按下 / 按下并释放 |
| `bs` | `n` | 退格 N 次 |
| `ime` / `ime_toggle` / `ime_refresh` | — | 输入法切换与刷新 |
| `auth` | `pin` | PIN 认证 |
| `approval_resp` | `r` | 设备审批（accept / reject） |

**服务端 → 客户端：**

| 消息 | 说明 |
|------|------|
| `auth_required` / `auth_fail` | 需要 PIN 认证 / 认证失败 |
| `ctrl_ok` | 获得控制权 |
| `wait` | 等待（被拒绝 / 超时 / 忙） |
| `approval_req` | 新设备请求连接 |
| `ime_init` / `ime_state` | 输入法状态初始化 / 变化 |

## 许可证

[MIT](LICENSE)
