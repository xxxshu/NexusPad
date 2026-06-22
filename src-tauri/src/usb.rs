/// USB AOA (Android Open Accessory) 传输通道
///
/// 实现 Tauri 服务端作为 USB Host，检测 Android 设备、执行 AOA 握手、
/// 通过 Bulk Transfer 交换 TLV 帧。
use std::sync::Arc;
use std::time::Duration;

use anyhow::{anyhow, Result};
use tokio::sync::{broadcast, mpsc, Mutex};
use tracing::{info, warn};

use crate::codec::{TlvFrame, FRAME_CONTROL, FRAME_GAMEPAD, FRAME_HEARTBEAT, FRAME_INPUT, FRAME_SYSTEM, GamepadStateBinary};
use crate::protocol::{ClientMessage, ServerMsg};
use crate::server::ServerState;

// ─── AOA 协议常量 ──────────────────────────────────────────

/// 已知的 Android 设备 Vendor IDs
const ANDROID_VENDOR_IDS: &[u16] = &[
    0x18D1, // Google
    0x22B8, // Motorola
    0x04E8, // Samsung
    0x2717, // Xiaomi
    0x12D1, // Huawei
    0x0BB4, // HTC
    0x19D2, // ZTE
    0x109B, // Hisense (Nexus 6)
    0x17EF, // Lenovo
    0x0E8D, // MediaTek (various Chinese brands)
];

/// AOA Product IDs (设备进入 Accessory 模式后)
const AOA_PID_ACCESSORY: u16 = 0x2D00;
const AOA_PID_ACCESSORY_ADB: u16 = 0x2D01;
const AOA_PID_AUDIO: u16 = 0x2D02;
const AOA_PID_AUDIO_ADB: u16 = 0x2D03;
const AOA_PID_ACCESSORY_AUDIO: u16 = 0x2D04;
const AOA_PID_ACCESSORY_AUDIO_ADB: u16 = 0x2D05;

/// AOA Control Transfer Requests
const AOA_SET_STRING_REQUEST: u8 = 52; // 0x34
const AOA_START_ACCESSORY_REQUEST: u8 = 53; // 0x35

/// AOA String Indices
const AOA_STRING_MANUFACTURER: u16 = 0;
const AOA_STRING_MODEL: u16 = 1;
const AOA_STRING_DESCRIPTION: u16 = 2;
const AOA_STRING_VERSION: u16 = 3;
const AOA_STRING_URL: u16 = 4;
const AOA_STRING_SERIAL: u16 = 5;

/// NexusPad AOA 设备信息
const AOA_MANUFACTURER: &str = "NexusPad";
const AOA_MODEL: &str = "NexusPad Controller";
const AOA_DESCRIPTION: &str = "NexusPad USB Accessory";
const AOA_VERSION: &str = "1.0";
const AOA_URL: &str = "https://nexuspad.app";
const AOA_SERIAL: &str = "NP-001";

// ─── 设备检测 ──────────────────────────────────────────────

/// 检查是否为已知的 AOA Product ID
fn is_aoa_pid(pid: u16) -> bool {
    matches!(
        pid,
        AOA_PID_ACCESSORY
            | AOA_PID_ACCESSORY_ADB
            | AOA_PID_AUDIO
            | AOA_PID_AUDIO_ADB
            | AOA_PID_ACCESSORY_AUDIO
            | AOA_PID_ACCESSORY_AUDIO_ADB
    )
}

/// 扫描已连接的 USB 设备，寻找尚未进入 AOA 模式的 Android 设备
fn find_android_device() -> Result<Option<(rusb::Device<rusb::GlobalContext>, String)>> {
    let devices = rusb::devices()?;
    let mut found_any = false;
    for device in devices.iter() {
        let desc = match device.device_descriptor() {
            Ok(d) => d,
            Err(e) => {
                warn!("USB: failed to read device descriptor: {}", e);
                continue;
            }
        };
        let vid = desc.vendor_id();
        let pid = desc.product_id();
        // 记录所有 USB 设备（调试用）
        if vid != 0 && pid != 0 {
            info!("USB device: {:04X}:{:04X} (class={:02X})", vid, pid, desc.class_code());
        }
        if ANDROID_VENDOR_IDS.contains(&vid) && !is_aoa_pid(pid) {
            let product = format!("Android {:04X}:{:04X}", vid, pid);
            info!("Found Android device: {} — attempting AOA handshake", product);
            found_any = true;
            return Ok(Some((device, product)));
        }
    }
    if !found_any {
        info!("USB: no Android devices found (scanned {} devices)", devices.len());
    }
    Ok(None)
}

/// 扫描已进入 AOA 模式的设备
fn find_aoa_device() -> Result<Option<(rusb::Device<rusb::GlobalContext>, String)>> {
    let devices = rusb::devices()?;
    for device in devices.iter() {
        let desc = match device.device_descriptor() {
            Ok(d) => d,
            Err(_) => continue,
        };
        if is_aoa_pid(desc.product_id()) {
            let name = format!(
                "NexusPad AOA {:04X}:{:04X}",
                desc.vendor_id(),
                desc.product_id()
            );
            info!("Found AOA device: {}", name);
            return Ok(Some((device, name)));
        }
    }
    Ok(None)
}

// ─── AOA 握手 ──────────────────────────────────────────────

/// 向 Android 设备发送 AOA 字符串设置请求
fn set_aoa_string(
    handle: &rusb::DeviceHandle<rusb::GlobalContext>,
    index: u16,
    value: &str,
) -> Result<usize> {
    let request_type = rusb::request_type(
        rusb::Direction::Out,
        rusb::RequestType::Vendor,
        rusb::Recipient::Device,
    );
    handle
        .write_control(
            request_type,
            AOA_SET_STRING_REQUEST,
            0,
            index,
            value.as_bytes(),
            Duration::from_secs(1),
        )
        .map_err(|e| anyhow!("AOA set string {} failed: {}", index, e))
}

/// 发送 AOA Start Accessory 命令
fn start_accessory(handle: &rusb::DeviceHandle<rusb::GlobalContext>) -> Result<usize> {
    let request_type = rusb::request_type(
        rusb::Direction::Out,
        rusb::RequestType::Vendor,
        rusb::Recipient::Device,
    );
    handle
        .write_control(
            request_type,
            AOA_START_ACCESSORY_REQUEST,
            0,
            0,
            &[],
            Duration::from_secs(1),
        )
        .map_err(|e| anyhow!("AOA start accessory failed: {}", e))
}

/// 对 Android 设备执行完整的 AOA 握手
///
/// 1. 设置 AOA 字符串（制造商、型号等）
/// 2. 发送 Start Accessory 命令
/// 3. 设备将重新枚举为 AOA Accessory
fn perform_aoa_handshake(
    device: &rusb::Device<rusb::GlobalContext>,
) -> Result<()> {
    let handle = device.open().map_err(|e| {
        warn!("AOA handshake: failed to open device — {}", e);
        match e {
            rusb::Error::Access => anyhow!(
                "USB 驱动权限不足。请安装 WinUSB 驱动（使用 Zadig 工具）。错误: {}", e
            ),
            rusb::Error::NoDevice => anyhow!("USB 设备已断开: {}", e),
            _ => anyhow!("无法打开 USB 设备: {}", e),
        }
    })?;

    // 某些设备需要先 detach kernel driver
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    {
        let _ = handle.detach_kernel_driver(0);
    }

    info!("AOA handshake: setting accessory strings...");
    set_aoa_string(&handle, AOA_STRING_MANUFACTURER, AOA_MANUFACTURER)?;
    set_aoa_string(&handle, AOA_STRING_MODEL, AOA_MODEL)?;
    set_aoa_string(&handle, AOA_STRING_DESCRIPTION, AOA_DESCRIPTION)?;
    set_aoa_string(&handle, AOA_STRING_VERSION, AOA_VERSION)?;
    set_aoa_string(&handle, AOA_STRING_URL, AOA_URL)?;
    set_aoa_string(&handle, AOA_STRING_SERIAL, AOA_SERIAL)?;

    info!("AOA handshake: starting accessory mode...");
    start_accessory(&handle)?;

    Ok(())
}

// ─── Bulk Transfer 读写 ────────────────────────────────────

/// 查找 Bulk In 和 Bulk Out 端点
fn find_bulk_endpoints(
    device: &rusb::Device<rusb::GlobalContext>,
) -> Result<(u8, u8, u16)> {
    let desc = device.device_descriptor()?;
    let config_desc = device.config_descriptor(0)?;

    let mut bulk_in = None;
    let mut bulk_out = None;
    let mut max_packet_size = 512u16;

    for iface in config_desc.interfaces() {
        for iface_desc in iface.descriptors() {
            for ep in iface_desc.endpoint_descriptors() {
                if ep.transfer_type() == rusb::TransferType::Bulk {
                    if ep.direction() == rusb::Direction::In && bulk_in.is_none() {
                        bulk_in = Some(ep.address());
                        max_packet_size = ep.max_packet_size();
                    } else if ep.direction() == rusb::Direction::Out && bulk_out.is_none() {
                        bulk_out = Some(ep.address());
                    }
                }
            }
        }
    }

    let bulk_in = bulk_in.ok_or_else(|| anyhow!("No Bulk In endpoint found"))?;
    let bulk_out = bulk_out.ok_or_else(|| anyhow!("No Bulk Out endpoint found"))?;

    info!(
        "USB endpoints: Bulk In=0x{:02X}, Bulk Out=0x{:02X}, max_packet={}",
        bulk_in, bulk_out, max_packet_size
    );

    Ok((bulk_in, bulk_out, max_packet_size))
}

// ─── USB 通道发送器 ────────────────────────────────────────

/// USB 发送端，通过 mpsc channel 接收数据，写入 Bulk Out
struct UsbSender {
    tx: mpsc::UnboundedSender<Vec<u8>>,
}

impl UsbSender {
    fn new(tx: mpsc::UnboundedSender<Vec<u8>>) -> Self {
        Self { tx }
    }

    fn send(&self, data: Vec<u8>) -> Result<()> {
        self.tx
            .send(data)
            .map_err(|_| anyhow!("USB sender channel closed"))
    }

    fn send_tlv(&self, frame_type: u8, payload: &[u8]) -> Result<()> {
        let frame = TlvFrame {
            frame_type,
            payload: payload.to_vec(),
        };
        self.send(frame.encode())
    }

    fn send_json(&self, frame_type: u8, json: &str) -> Result<()> {
        self.send_tlv(frame_type, json.as_bytes())
    }
}

// ─── USB 主循环 ────────────────────────────────────────────

/// USB AOA 监听器主入口
///
/// 在后台 tokio task 中运行，持续监听 USB 设备连接。
/// 当检测到 AOA 设备时，建立 Bulk Transfer 通道并开始处理消息。
pub async fn start_usb_listener(
    state: Arc<ServerState>,
    mut stop_rx: broadcast::Receiver<()>,
) {
    info!("USB AOA listener started");

    loop {
        // 检查是否收到停止信号
        if stop_rx.try_recv().is_ok() {
            info!("USB AOA listener stopping");
            break;
        }

        // 阶段 1: 尝试查找已有的 AOA 设备
        match find_aoa_device() {
            Ok(Some((device, name))) => {
                info!("AOA device found: {}", name);
                if let Err(e) = handle_aoa_device(device, name, &state, &mut stop_rx).await {
                    warn!("AOA device handler error: {}", e);
                }
                // 设备断开后继续循环，等待下一个设备
                tokio::time::sleep(Duration::from_secs(1)).await;
                continue;
            }
            Ok(None) => {}
            Err(e) => {
                warn!("USB scan error: {}", e);
            }
        }

        // 阶段 2: 尝试查找未进入 AOA 模式的 Android 设备并握手
        match find_android_device() {
            Ok(Some((device, name))) => {
                info!("Android device found: {} — initiating AOA handshake", name);
                match perform_aoa_handshake(&device) {
                    Ok(()) => {
                        info!("AOA handshake sent, waiting for device re-enumeration...");
                        // 等待设备重新枚举为 AOA Accessory
                        tokio::time::sleep(Duration::from_secs(2)).await;

                        // 重新扫描查找 AOA 设备
                        match find_aoa_device() {
                            Ok(Some((aoa_device, aoa_name))) => {
                                info!("AOA device ready: {}", aoa_name);
                                if let Err(e) =
                                    handle_aoa_device(aoa_device, aoa_name, &state, &mut stop_rx)
                                        .await
                                {
                                    warn!("AOA device handler error: {}", e);
                                }
                            }
                            Ok(None) => {
                                warn!("AOA handshake sent but device not re-enumerated");
                            }
                            Err(e) => {
                                warn!("Post-handshake scan error: {}", e);
                            }
                        }
                    }
                    Err(e) => {
                        warn!("AOA handshake failed: {}", e);
                    }
                }
                tokio::time::sleep(Duration::from_secs(2)).await;
            }
            Ok(None) => {
                // 没有设备，等待后再扫描
                tokio::time::sleep(Duration::from_secs(3)).await;
            }
            Err(e) => {
                warn!("USB device scan error: {}", e);
                tokio::time::sleep(Duration::from_secs(3)).await;
            }
        }
    }
}

/// 处理一个 AOA 设备的完整生命周期
///
/// 1. 打开设备，找到 Bulk 端点
/// 2. 建立读写通道
/// 3. 无需认证，直接赋予控制权
/// 4. 进入消息循环
async fn handle_aoa_device(
    device: rusb::Device<rusb::GlobalContext>,
    device_name: String,
    state: &Arc<ServerState>,
    stop_rx: &mut broadcast::Receiver<()>,
) -> Result<()> {
    // 打开设备并查找端点
    let mut handle = device.open()?;

    // Detach kernel driver if needed
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    {
        let _ = handle.detach_kernel_driver(0);
    }

    // Claim interface 0
    handle.claim_interface(0)?;

    let (bulk_in, bulk_out, _max_packet) = find_bulk_endpoints(&device)?;

    // 创建发送通道
    let (send_tx, mut send_rx) = mpsc::unbounded_channel::<Vec<u8>>();

    // 标记为活跃控制器（免认证）
    {
        let mut active_usb = state.active_usb.lock().await;
        if active_usb.is_some() {
            warn!("USB: another USB device already active, rejecting");
            return Err(anyhow!("USB slot already occupied"));
        }
        *active_usb = Some(send_tx.clone());
    }

    let usb_sender = UsbSender::new(send_tx);
    *state.usb_device_name.lock().await = Some(device_name.clone());

    // 踢掉 WS 控制器（如果有）
    if let Some((_, old_ws_tx)) = state.active_ws.lock().await.take() {
        let kick = serde_json::json!({"a": "wait", "reason": "kicked"}).to_string();
        let _ = old_ws_tx.send(axum::extract::ws::Message::Text(kick.into()));
        let _ = old_ws_tx.send(axum::extract::ws::Message::Close(Some(
            axum::extract::ws::CloseFrame {
                code: 4001,
                reason: "USB controller".into(),
            },
        )));
    }

    // 发送 CtrlOk（免认证）
    let ctrl_ok = serde_json::to_string(&ServerMsg::CtrlOk { proot: None }).unwrap();
    let ctrl_ok_frame = TlvFrame {
        frame_type: FRAME_CONTROL,
        payload: ctrl_ok.into_bytes(),
    };
    let _ = usb_sender.send(ctrl_ok_frame.encode());

    // 推送 IME 状态
    state.push_ime_status().await;

    state.emit_gui_event(
        "device-authenticated",
        serde_json::json!({ "device_name": device_name }),
    );
    state.send_event(format!("✅ {} (USB) 已连接", device_name));
    info!("USB controller active: {}", device_name);

    // ─── Bulk 读写循环 ──────────────────────────────────────

    let read_handle = Arc::new(Mutex::new(handle));
    let write_handle = read_handle.clone();

    // 读线程: Bulk In → TLV 解码 → 消息分发
    let state_read = state.clone();
    let read_task = tokio::spawn(async move {
        let mut buf = vec![0u8; 4096];
        let mut pending = Vec::new();
        loop {
            let n = {
                let h = read_handle.lock().await;
                match h.read_bulk(bulk_in, &mut buf, Duration::from_millis(100)) {
                    Ok(n) => n,
                    Err(rusb::Error::Timeout) => continue,
                    Err(rusb::Error::NoDevice) => {
                        info!("USB: device disconnected (NoDevice)");
                        break;
                    }
                    Err(rusb::Error::Pipe) => {
                        info!("USB: device disconnected (Pipe)");
                        break;
                    }
                    Err(e) => {
                        warn!("USB read error: {}", e);
                        break;
                    }
                }
            };

            if n == 0 {
                continue;
            }

            // 追加到待处理缓冲区
            pending.extend_from_slice(&buf[..n]);

            // 尝试解码 TLV 帧
            while let Some((frame, consumed)) = TlvFrame::decode(&pending) {
                pending.drain(..consumed);

                let msg = match frame.frame_type {
                    FRAME_GAMEPAD => {
                        GamepadStateBinary::decode(&frame.payload)
                            .map(ClientMessage::BinaryGamepad)
                    }
                    FRAME_INPUT => {
                        if frame.payload.is_empty() {
                            continue;
                        }
                        crate::codec::decode_input_move(&frame.payload)
                            .map(|(x, y)| ClientMessage::BinaryMove { x, y })
                            .or_else(|| {
                                crate::codec::decode_input_scroll(&frame.payload)
                                    .map(|(x, y)| ClientMessage::BinaryScroll { x, y })
                            })
                    }
                    FRAME_CONTROL => {
                        String::from_utf8(frame.payload)
                            .ok()
                            .and_then(|s| ClientMessage::from_text(&s))
                    }
                    FRAME_HEARTBEAT => Some(ClientMessage::Heartbeat),
                    _ => None,
                };

                if let Some(msg) = msg {
                    crate::server::handle_client_message_static(msg, &state_read, "usb").await;
                }
            }
        }
    });

    // 写线程: channel → Bulk Out
    let write_task = tokio::spawn(async move {
        while let Some(data) = send_rx.recv().await {
            let h = write_handle.lock().await;
            match h.write_bulk(bulk_out, &data, Duration::from_millis(100)) {
                Ok(_) => {}
                Err(rusb::Error::NoDevice) | Err(rusb::Error::Pipe) => {
                    info!("USB write: device disconnected");
                    break;
                }
                Err(e) => {
                    warn!("USB write error: {}", e);
                }
            }
        }
    });

    // 等待停止信号或设备断开
    tokio::select! {
        _ = stop_rx.recv() => {
            info!("USB: received stop signal");
        }
        _ = read_task => {
            info!("USB: read task ended (device disconnected)");
        }
    }

    // 清理
    write_task.abort();

    // 销毁虚拟手柄
    {
        let mut gp = state.gamepad.lock().await;
        gp.destroy();
    }

    // 释放 USB 控制器槽位
    {
        let mut active_usb = state.active_usb.lock().await;
        *active_usb = None;
    }
    *state.usb_device_name.lock().await = None;

    state.send_event(format!("❌ {} (USB) 已断开", device_name));
    state.emit_gui_event(
        "device-disconnected",
        serde_json::json!({ "device_name": device_name }),
    );

    info!("USB controller disconnected: {}", device_name);
    Ok(())
}

// ─── 驱动检测 ──────────────────────────────────────────────

/// 检测 USB 驱动是否可用
///
/// 检查 rusb 是否能枚举设备，以及能否打开 Android/AOA 设备
pub fn check_usb_driver() -> bool {
    match rusb::devices() {
        Ok(devices) => {
            let mut found_android = false;
            for device in devices.iter() {
                let desc = match device.device_descriptor() {
                    Ok(d) => d,
                    Err(_) => continue,
                };
                let vid = desc.vendor_id();
                let pid = desc.product_id();
                if vid == 0 { continue; }
                if ANDROID_VENDOR_IDS.contains(&vid) || is_aoa_pid(pid) {
                    found_android = true;
                    // 尝试打开设备——成功说明 WinUSB 驱动已装
                    match device.open() {
                        Ok(_) => {
                            info!("USB driver check: device {:04X}:{:04X} opened OK", vid, pid);
                            return true;
                        }
                        Err(e) => {
                            warn!("USB driver check: device {:04X}:{:04X} open failed: {}", vid, pid, e);
                            return false; // 找到设备但打不开 = 驱动问题
                        }
                    }
                }
            }
            // 没有找到 Android 设备，但 rusb 本身可用（驱动正常）
            if !found_android {
                info!("USB driver check: rusb OK but no Android devices connected");
            }
            true
        }
        Err(e) => {
            warn!("USB driver check: rusb not available: {}", e);
            false // libusb 本身不可用
        }
    }
}
