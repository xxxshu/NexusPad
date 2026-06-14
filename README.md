# NexusPad

> 把手机变成电脑的无线触控板和键盘 —— 同一局域网下，扫码即连。

## 功能

- **触控板** — 单指移动、双指滚动、点击/双击/长按拖动
- **键盘** — 实时输入、退格、回车，支持拼音输入法
- **功能键** — Esc / Tab / Del / 方向键 / Ctrl / Shift / Alt，支持锁定修饰键组合
- **扫码连接** — 桌面端显示二维码，手机扫码直连
- **PIN 配对** — 6 位数字配对码，每次认证后自动刷新
- **连接审批** — 已连接设备可批准/拒绝新设备接入
- **全新 UI** — v0.2.0 全新现代化界面设计，桌面端与手机端同步焕新
- **跨平台** — Windows 10/11、Linux（Ubuntu / Debian）

## 截图

<div>
  <img src="src-tauri/icons/icon.svg" width="100" alt="NexusPad Logo">
</div>

## 安装

### 从 Releases 下载

前往 [Releases](https://github.com/xxxshu/remote-touchpad/releases) 页面下载对应平台的安装包：

| 平台 | 格式 |
|------|------|
| Windows | `.exe` 安装程序 (NSIS) |
| Linux (Debian/Ubuntu) | `.deb` 安装包 |
| Linux (ARM64) | `.deb` 安装包 |

### 从源码构建

**前置条件：**

- [Node.js](https://nodejs.org/) (18+)
- [Rust](https://rustup.rs/) (1.70+)
- [Tauri CLI](https://tauri.app/start/prerequisites/) v2

```bash
cargo install tauri-cli --version "^2"
```

**Linux 额外依赖（Ubuntu/Debian）：**

```bash
sudo apt install libxdo-dev libxcb-shape0-dev libxcb-xfixes0-dev \
  libgtk-3-dev libwebkit2gtk-4.1-dev libappindicator3-dev \
  patchelf librsvg2-dev libssl-dev
```

> Linux 用户还需确保有 uinput 权限：将自己加入 `input` 组，或添加 udev 规则。

**构建 & 运行：**

```bash
git clone https://github.com/xxxshu/remote-touchpad.git
cd remote-touchpad

# 安装前端依赖
cd src-tauri/ui && npm install && cd ../..

# 开发模式
cargo tauri dev

# 打包发布
cargo tauri build
```

生成的安装包位于 `src-tauri/target/release/bundle/`。

## 使用方法

1. 启动应用，设置端口（默认 8765），点击「启动」
2. 手机扫描二维码，或在浏览器输入显示的地址
3. 在手机上输入 6 位 PIN 配对码
4. 如已有设备连接，需在电脑端批准新设备
5. 开始使用！

## 技术架构

```
手机浏览器                          电脑
┌──────────────────┐    WebSocket    ┌────────────────────────────┐
│  frontend/       │ ◄────────────► │  axum HTTP + WS 服务器      │
│                  │    :8765       │  (server.rs)               │
│  触控板手势       │                │                            │
│  键盘输入        │   JSON 消息     │  enigo 输入模拟             │
│  功能键面板       │ ─────────────► │  arboard 剪贴板             │
│  PIN 认证        │                │  PIN 配对 + 审批状态机       │
└──────────────────┘                ├────────────────────────────┤
                                    │  Tauri v2 桌面 GUI          │
                                    │  (ui/ — Vite + React)      │
                                    │  二维码 · 设备状态 · 窗口控制 │
                                    └────────────────────────────┘
```

### 技术栈

| 组件 | 技术 |
|------|------|
| 桌面框架 | Tauri v2 |
| 后端语言 | Rust (tokio + axum) |
| WebSocket | tokio-tungstenite |
| 输入模拟 | enigo (跨平台) |
| 剪贴板 | arboard |
| 二维码 | qrcode crate |
| 手机端前端 | 原生 HTML / CSS / JS |
| 桌面端 UI | Vite + React + TypeScript |

## 开发

### 项目结构

```
remote-touchpad/
├── frontend/                # 手机端 Web 前端
│   ├── index.html           # 主页面（含内联样式和图标）
│   ├── app.js               # 核心交互逻辑
│   └── pinyin-dict.js       # 拼音词库
│
├── src-tauri/               # Rust 后端 + Tauri GUI
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── capabilities/        # Tauri 权限配置
│   ├── icons/               # 应用图标（ico/png/svg）
│   ├── ui/                  # Tauri 桌面管理界面
│   │   ├── src/             # React 组件源码
│   │   ├── dist/            # 构建产物
│   │   ├── package.json
│   │   └── vite.config.ts
│   └── src/
│       ├── main.rs
│       ├── lib.rs           # Tauri commands
│       ├── server.rs        # HTTP + WebSocket 服务器
│       ├── input.rs         # 跨平台输入模拟
│       └── protocol.rs      # 消息协议
│
└── .github/workflows/       # CI: 多平台自动构建
```

### WebSocket 消息协议

**客户端 → 服务器：**

| 动作 | 字段 | 说明 |
|------|------|------|
| `mv` | `x`, `y` | 鼠标移动 |
| `clk` | `b` (1/3) | 单击（左/右） |
| `dbl` | — | 双击 |
| `md` | `b` | 鼠标按下 |
| `mu` | `b` | 鼠标释放 |
| `scr` | `y` | 滚动（非线性加速） |
| `type` | `t` | 输入文字 |
| `key` | `k` | 按键（如 `ctrl+c`） |
| `bs` | `n` | 退格 N 次 |

**服务器 → 客户端：**

| 消息 | 说明 |
|------|------|
| `auth_required` | 需要 PIN 认证 |
| `ctrl_ok` | 获得控制权 |
| `approval_req` | 新设备请求连接 |

## 许可证

MIT
