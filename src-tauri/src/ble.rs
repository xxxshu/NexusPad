/// BLE (Bluetooth Low Energy) GATT Server 传输通道
///
/// 架构: PC 作为 BLE Peripheral 广播 NexusPad 服务，手机作为 Central 连接。
/// GATT Service: 4e5c0001-f2cb-4931-a20c-7b1981273948
///   TX (Notify):  4e5c0002-f2cb-4931-a20c-7b1981273948 (Server→Client)
///   RX (WriteNoRsp): 4e5c0003-f2cb-4931-a20c-7b1981273948 (Client→Server)
///
/// Windows 实现使用 WinRT GattServiceProvider API。
/// TODO: WinRT API 需在真实设备上测试验证后填充具体调用。
use std::sync::Arc;

use tokio::sync::broadcast;
use tracing::{info, warn};

use crate::server::ServerState;

// ─── BLE UUID 常量 ─────────────────────────────────────────

pub const SERVICE_UUID: &str = "4e5c0001-f2cb-4931-a20c-7b1981273948";
pub const CHAR_TX_UUID: &str = "4e5c0002-f2cb-4931-a20c-7b1981273948";
pub const CHAR_RX_UUID: &str = "4e5c0003-f2cb-4931-a20c-7b1981273948";

// ─── BLE GATT Server 主入口 ────────────────────────────────

/// 启动 BLE GATT Server (所有平台统一入口)
pub async fn start_ble_server(
    state: Arc<ServerState>,
    mut stop_rx: broadcast::Receiver<()>,
) {
    info!("BLE GATT Server: starting...");

    #[cfg(target_os = "windows")]
    {
        match run_windows_ble_server(&state, &mut stop_rx).await {
            Ok(()) => info!("BLE server exited normally"),
            Err(e) => warn!("BLE server error: {}", e),
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        info!("BLE GATT Server: not available on this platform");
        let _ = stop_rx.recv().await;
    }

    // Cleanup
    {
        let mut active_ble = state.active_ble.lock().await;
        *active_ble = None;
    }
    *state.ble_device_name.lock().await = None;
    state.send_event("❌ BLE 服务已停止".to_string());
}

/// Check if BLE is available on this system
pub fn check_ble_available() -> bool {
    #[cfg(target_os = "windows")]
    { true }
    #[cfg(not(target_os = "windows"))]
    { false }
}

// ─── Windows 实现 ──────────────────────────────────────────

#[cfg(target_os = "windows")]
async fn run_windows_ble_server(
    state: &Arc<ServerState>,
    stop_rx: &mut broadcast::Receiver<()>,
) -> anyhow::Result<()> {
    use windows::core::GUID;
    use windows::Devices::Bluetooth::GenericAttributeProfile::*;
    use windows::Foundation::TypedEventHandler;
    use windows::Storage::Streams::DataReader;

    use crate::codec::{self, TlvFrame, FRAME_CONTROL, FRAME_HEARTBEAT, FRAME_INPUT};
    use crate::protocol::ClientMessage;

    // Helper: parse UUID string to GUID
    fn parse_guid(s: &str) -> GUID {
        let clean: String = s.chars().filter(|c| *c != '-').collect();
        if clean.len() != 32 { return GUID::zeroed(); }
        let p = |start, len| u64::from_str_radix(&clean[start..start + len], 16).unwrap_or(0);
        GUID::from_values(
            p(0, 8) as u32, p(8, 4) as u16, p(12, 4) as u16,
            [p(16, 2) as u8, p(18, 2) as u8, p(20, 2) as u8, p(22, 2) as u8,
             p(24, 2) as u8, p(26, 2) as u8, p(28, 2) as u8, p(30, 2) as u8],
        )
    }

    info!("BLE GATT Server: creating service provider...");

    // 1. 创建 GATT Service Provider
    let service_guid = parse_guid(SERVICE_UUID);
    let provider_result = GattServiceProvider::CreateAsync(service_guid)?.get()?;
    let provider = provider_result.ServiceProvider()?;
    info!("BLE: service provider created");

    // 2. 创建 TX Characteristic (Notify) — 不要求加密，避免触发配对
    let tx_guid = parse_guid(CHAR_TX_UUID);
    let tx_params = GattLocalCharacteristicParameters::new()?;
    tx_params.SetCharacteristicProperties(GattCharacteristicProperties::Notify)?;
    tx_params.SetReadProtectionLevel(GattProtectionLevel::Plain)?;
    let tx_result = provider.Service()?.CreateCharacteristicAsync(tx_guid, &tx_params)?.get()?;
    let tx_char = tx_result.Characteristic()?;
    info!("BLE: TX characteristic created (Notify, Plain)");

    // 3. 创建 RX Characteristic (WriteWithoutResponse) — 不要求加密
    let rx_guid = parse_guid(CHAR_RX_UUID);
    let rx_params = GattLocalCharacteristicParameters::new()?;
    rx_params.SetCharacteristicProperties(
        GattCharacteristicProperties::WriteWithoutResponse,
    )?;
    rx_params.SetWriteProtectionLevel(GattProtectionLevel::Plain)?;
    let rx_result = provider.Service()?.CreateCharacteristicAsync(rx_guid, &rx_params)?.get()?;
    let rx_char = rx_result.Characteristic()?;
    info!("BLE: RX characteristic created (WriteWithoutResponse, Plain)");

    // 4. 监听 RX 写入事件
    let state_write = state.clone();
    rx_char.WriteRequested(&TypedEventHandler::<
        GattLocalCharacteristic,
        GattWriteRequestedEventArgs,
    >::new(move |_char, args| {
        if let Some(args) = args.as_ref() {
            let request = args.GetRequestAsync()?.get()?;
            let value = request.Value()?;
            let reader = DataReader::FromBuffer(&value)?;
            let len = reader.UnconsumedBufferLength()? as usize;
            let mut buf = vec![0u8; len];
            reader.ReadBytes(&mut buf)?;
            request.Respond()?;

            // 解码 TLV 帧并分发到消息处理器
            if let Some((frame, _)) = TlvFrame::decode(&buf) {
                let msg = match frame.frame_type {
                    FRAME_INPUT => {
                        codec::decode_input_move(&frame.payload)
                            .map(|(x, y)| ClientMessage::BinaryMove { x, y })
                            .or_else(|| {
                                codec::decode_input_scroll(&frame.payload)
                                    .map(|(x, y)| ClientMessage::BinaryScroll { x, y })
                            })
                    }
                    FRAME_HEARTBEAT => Some(ClientMessage::Heartbeat),
                    FRAME_CONTROL => String::from_utf8(frame.payload)
                        .ok()
                        .and_then(|s| ClientMessage::from_text(&s)),
                    _ => None,
                };
                if let Some(msg) = msg {
                    let state = state_write.clone();
                    tokio::spawn(async move {
                        crate::server::handle_client_message_static(msg, &state, "ble").await;
                    });
                }
            }
        }
        Ok(())
    }))?;

    // 5. 开始广播
    let mut adv_params = GattServiceProviderAdvertisingParameters::new()?;
    adv_params.SetIsConnectable(true)?;
    adv_params.SetIsDiscoverable(true)?;
    provider.StartAdvertisingWithParameters(&adv_params)?;
    info!("BLE GATT Server: advertising as 'NexusPad'");

    // 6. 等待停止信号
    stop_rx.recv().await.ok();

    // 7. 停止广播
    provider.StopAdvertising()?;
    info!("BLE GATT Server: advertising stopped");

    Ok(())
}
