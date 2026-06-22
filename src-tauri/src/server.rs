use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::ConnectInfo;
use axum::extract::State as AxumState;
use axum::http::HeaderMap;
use axum::response::IntoResponse;
use axum::routing::get;
use axum::Router;
use futures_util::{SinkExt, StreamExt};
use tokio::net::TcpListener;
use tokio::sync::{broadcast, mpsc, Mutex, oneshot};
use serde_json;
use anyhow::Result;
use tauri::Emitter;
use tracing::{info, warn};

use crate::gamepad::GamepadManager;
use crate::input::InputSimulator;
use crate::platform::{self, PlatformHandler};
use crate::protocol::{ClientMessage, ClientMsg, ServerMsg};

/// Frontend files embedded in the binary at compile time
#[derive(Clone)]
struct EmbeddedFile {
    content: &'static [u8],
    mime: &'static str,
}

fn embedded_frontend() -> HashMap<&'static str, EmbeddedFile> {
    let mut m: HashMap<&'static str, EmbeddedFile> = HashMap::new();
    m.insert("", EmbeddedFile { content: include_bytes!("../../frontend/index.html"), mime: "text/html; charset=utf-8" });
    m.insert("index.html", EmbeddedFile { content: include_bytes!("../../frontend/index.html"), mime: "text/html; charset=utf-8" });
    m.insert("style.css", EmbeddedFile { content: include_bytes!("../../frontend/style.css"), mime: "text/css; charset=utf-8" });
    m.insert("app.js", EmbeddedFile { content: include_bytes!("../../frontend/app.js"), mime: "application/javascript; charset=utf-8" });
    m.insert("pinyin-dict.js", EmbeddedFile { content: include_bytes!("../../frontend/pinyin-dict.js"), mime: "application/javascript; charset=utf-8" });
    m.insert("iconfont/iconfont.js", EmbeddedFile { content: include_bytes!("../../frontend/iconfont/iconfont.js"), mime: "application/javascript; charset=utf-8" });
    m
}

/// Shared server state
pub struct ServerState {
    pub input: Arc<Mutex<InputSimulator>>,
    /// Platform-specific IME handler
    pub platform: Box<dyn PlatformHandler>,
    /// Custom IME toggle key (e.g. "shift", "ctrl+space"), None = platform default
    pub ime_toggle_key: Option<String>,
    /// Active controller: (addr, sender_to_ws)
    pub active_ws: Arc<Mutex<Option<(SocketAddr, mpsc::UnboundedSender<Message>)>>>,
    /// Connected device name (from User-Agent)
    pub connected_device: Arc<Mutex<Option<String>>>,
    /// Pending controller waiting for approval
    pub pending_ws: Arc<Mutex<Option<SocketAddr>>>,
    /// Channel to send approval response from active → pending handler
    pub approval_tx: Arc<Mutex<Option<oneshot::Sender<String>>>>,
    /// Address of device currently in the connecting/auth phase (before becoming active)
    pub connecting_addr: Arc<Mutex<Option<SocketAddr>>>,
    /// PIN code for authentication (wrapped in Mutex for interior mutability)
    pub pin: Mutex<String>,
    pub event_tx: broadcast::Sender<String>,
    pub frontend_dir: PathBuf,
    /// Tauri app handle for emitting events to the GUI
    pub app_handle: Option<tauri::AppHandle>,
    /// Last known IME status (for background monitor diff)
    pub last_ime_status: Arc<Mutex<String>>,
    /// Virtual gamepad manager (ViGEmBus)
    pub gamepad: Arc<Mutex<GamepadManager>>,
    /// Active USB controller sender (for writing TLV frames to USB device)
    pub active_usb: Arc<Mutex<Option<mpsc::UnboundedSender<Vec<u8>>>>>,
    /// Connected USB device name
    pub usb_device_name: Arc<Mutex<Option<String>>>,
    /// Active BLE controller sender (for writing TLV frames via Notify)
    pub active_ble: Arc<Mutex<Option<mpsc::UnboundedSender<Vec<u8>>>>>,
    /// Connected BLE device name
    pub ble_device_name: Arc<Mutex<Option<String>>>,
}

/// Generate a random 6-digit PIN
fn generate_pin() -> String {
    use rand::Rng;
    let pin = rand::rng().random_range(100000u32..=999999);
    format!("{}", pin)
}

impl ServerState {
    pub fn new(
        input: InputSimulator,
        frontend_dir: PathBuf,
        ime_toggle_key: Option<String>,
        app_handle: Option<tauri::AppHandle>,
    ) -> Self {
        let (event_tx, _) = broadcast::channel(100);
        Self {
            input: Arc::new(Mutex::new(input)),
            platform: platform::get_platform(),
            ime_toggle_key,
            active_ws: Arc::new(Mutex::new(None)),
            connected_device: Arc::new(Mutex::new(None)),
            pending_ws: Arc::new(Mutex::new(None)),
            approval_tx: Arc::new(Mutex::new(None)),
            connecting_addr: Arc::new(Mutex::new(None)),
            pin: Mutex::new(generate_pin()),
            event_tx,
            frontend_dir,
            app_handle,
            last_ime_status: Arc::new(Mutex::new("EN".to_string())),
            gamepad: Arc::new(Mutex::new(GamepadManager::new())),
            active_usb: Arc::new(Mutex::new(None)),
            usb_device_name: Arc::new(Mutex::new(None)),
            active_ble: Arc::new(Mutex::new(None)),
            ble_device_name: Arc::new(Mutex::new(None)),
        }
    }

    pub fn send_event(&self, msg: String) {
        let _ = self.event_tx.send(msg);
    }

    /// Send a text message to the active controller (WS, USB, or BLE)
    async fn send_to_active(&self, msg: &str) -> bool {
        // Check WebSocket first
        let active = self.active_ws.lock().await;
        if let Some((_, ref tx)) = *active {
            return tx.send(Message::Text(msg.into())).is_ok();
        }
        drop(active);

        // Check USB
        let active_usb = self.active_usb.lock().await;
        if let Some(ref tx) = *active_usb {
            let frame = crate::codec::TlvFrame {
                frame_type: crate::codec::FRAME_CONTROL,
                payload: msg.as_bytes().to_vec(),
            };
            return tx.send(frame.encode()).is_ok();
        }
        drop(active_usb);

        // Check BLE
        let active_ble = self.active_ble.lock().await;
        if let Some(ref tx) = *active_ble {
            let frame = crate::codec::TlvFrame {
                frame_type: crate::codec::FRAME_CONTROL,
                payload: msg.as_bytes().to_vec(),
            };
            return tx.send(frame.encode()).is_ok();
        }
        false
    }

    /// Read current IME status and push it to the active controller.
    pub async fn push_ime_status(&self) {
        let status = self.platform.get_ime_status();
        // Update cached status so the monitor doesn't re-push the same value
        *self.last_ime_status.lock().await = status.clone();
        let msg = serde_json::to_string(&ServerMsg::ImeInit { status }).unwrap();
        self.send_to_active(&msg).await;
    }

    /// Background task: poll IME status every 200ms, push to controller on change.
    /// This catches IME changes from ANY source: window focus, physical keyboard, etc.
    pub async fn run_ime_monitor(self: Arc<Self>) {
        loop {
            tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
            // Only poll when there's an active controller
            let has_active = self.active_ws.lock().await.is_some();
            if !has_active { continue; }

            let current = self.platform.get_ime_status();
            let mut last = self.last_ime_status.lock().await;
            if current != *last {
                info!("IME state changed: {} → {}", *last, current);
                *last = current.clone();
                let msg = serde_json::to_string(&ServerMsg::ImeInit { status: current }).unwrap();
                drop(last); // release lock before async send
                self.send_to_active(&msg).await;
            }
        }
    }

    /// Emit a Tauri event to the GUI frontend
    pub fn emit_gui_event(&self, event: &str, payload: serde_json::Value) {
        if let Some(ref handle) = self.app_handle {
            let _ = handle.emit(event, payload);
        }
    }
}

/// Detect if running in a proot/chroot environment
pub fn is_proot() -> bool {
    // Check common proot indicators
    std::env::var("TMOE_PROOT").is_ok()
        || std::env::var("PROOT").is_ok()
        || std::path::Path::new("/run/.containerenv").exists()
        || std::path::Path::new("/.proot").exists()
}

/// Virtual / VPN interface prefixes — the phone cannot reach addresses on
/// these interfaces. Includes both Linux and Windows VPN adapter names.
const VIRTUAL_PREFIXES: &[&str] = &[
    "lo", "tun", "tap", "wg", "docker", "veth", "br-", "virbr",
    "vgate", "rmnet", "dummy", "bond", "team", "vboxnet", "vmnet",
    "ztr", "ham", "ppp", "sstp", "vpn",
];

/// Check if an IPv4 address string is in RFC 1918 private ranges:
/// 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16.
/// Only these ranges are guaranteed to be directly reachable on a LAN.
/// Proxy Fake-IP ranges (e.g. 198.18.0.0/15 from Clash) are NOT private.
fn is_rfc1918_private(ip: &str) -> bool {
    if ip.starts_with("10.") {
        return true;
    }
    if ip.starts_with("192.168.") {
        return true;
    }
    if ip.starts_with("172.") {
        // 172.16.0.0 – 172.31.255.255
        if let Some(second) = ip.split('.').nth(1) {
            if let Ok(n) = second.parse::<u8>() {
                return (16..=31).contains(&n);
            }
        }
    }
    false
}

/// Get LAN IP address (prefer WiFi/Ethernet over virtual adapters).
///
/// Detection order:
/// 1. UDP connect trick — queries the kernel routing table to find the IP that
///    would be used for outbound traffic. This naturally handles proxy adapters,
///    TUN-mode proxies, and VPN configurations correctly.
///    If the result is on a virtual/VPN interface, skip to method 2.
/// 2. Interface enumeration via `local_ip_address` (2-second timeout to guard
///    against `getifaddrs()` stalling on ARM64 / Android / containers).
///    Collects ALL candidates and ranks them: preferred interfaces (wlan/eth)
///    with private IP > any non-virtual with private IP > preferred > any > first.
/// 3. `ip -o -4 addr show` fallback — same ranking as method 2, for environments
///    where getifaddrs() hangs but `ip` works (e.g., Android/busybox).
/// 4. UDP connect (unfiltered) — accept any non-loopback result as last resort.
/// 5. "127.0.0.1" as absolute last resort.
pub fn get_local_ip() -> String {
    // 1) Use UDP connect as a "hint" — it's fast and reflects kernel routing,
    //    but we MUST verify the result against real interfaces to avoid proxy/
    //    VPN adapter IPs (e.g. 198.18.0.x from Clash Fake-IP).
    let udp_ip = udp_local_ip_fast();

    // 2) Interface scan with timeout — finds real LAN addresses.
    //    If the UDP IP matches a real (non-virtual) interface, trust it.
    //    Otherwise, rank candidates by interface type and RFC 1918 private IP.
    let (tx, rx) = std::sync::mpsc::channel();
    let _ = std::thread::Builder::new()
        .name("local-ip-scan".into())
        .spawn(move || {
            let result = (|| -> Option<(String, bool)> {
                let addrs = local_ip_address::list_afinet_netifas().ok()?;
                let udp_ref = udp_ip.as_deref();
                let mut preferred_private = None; // wlan/eth + RFC 1918
                let mut any_private = None;        // non-virtual + RFC 1918
                let mut preferred_any = None;      // wlan/eth + any IP
                let mut any_non_virtual = None;    // non-virtual + any IP
                for (name, ip) in &addrs {
                    if let std::net::IpAddr::V4(v4) = ip {
                        let s = v4.to_string();
                        if s.starts_with("127.") || s.starts_with("169.254.") {
                            continue;
                        }
                        let lower = name.to_lowercase();
                        let is_preferred = lower.starts_with("wlan")
                            || lower.starts_with("eth")
                            || lower.starts_with("wi-fi");
                        let is_virtual = VIRTUAL_PREFIXES
                            .iter()
                            .any(|p| lower.starts_with(p));
                        let is_private = is_rfc1918_private(&s);

                        // If UDP IP matches a real (non-virtual) interface AND
                        // it's RFC 1918 private, it's verified — the kernel uses
                        // this interface for routing and the phone can reach it.
                        if Some(s.as_str()) == udp_ref && !is_virtual && is_private {
                            return Some((s, true));
                        }

                        if is_preferred && is_private && preferred_private.is_none() {
                            preferred_private = Some(s.clone());
                        }
                        if !is_virtual && is_private && any_private.is_none() {
                            any_private = Some(s.clone());
                        }
                        if is_preferred && preferred_any.is_none() {
                            preferred_any = Some(s.clone());
                        }
                        if !is_virtual && any_non_virtual.is_none() {
                            any_non_virtual = Some(s.clone());
                        }
                    }
                }
                // Only return a candidate if it has a private IP (safe for LAN).
                // Non-private IPs (e.g. 198.18.0.x from proxy Fake-IP) are NOT
                // reachable from the phone.
                preferred_private
                    .or(any_private)
                    .map(|ip| (ip, false))
            })();
            let _ = tx.send(result);
        });

    if let Ok(Some((ip, verified))) = rx.recv_timeout(std::time::Duration::from_secs(2)) {
        if verified {
            tracing::info!("get_local_ip via UDP + interface verify: {}", ip);
            return ip;
        }
        tracing::info!("get_local_ip via interface scan: {}", ip);
        return ip;
    }
    tracing::warn!("get_local_ip: interface scan timed out (2s), trying ip-addr fallback");

    // 3) `ip -o -4 addr show` — enumerate all interfaces and filter out
    //    virtual / VPN ones. On Android devices (common ARM64 targets),
    //    getifaddrs() often hangs but `ip` works fine via busybox.
    if let Some(ip) = ip_addr_local_ip() {
        tracing::info!("get_local_ip via ip-addr: {}", ip);
        return ip;
    }

    // 4) Absolute last resort
    "127.0.0.1".to_string()
}

/// Run `ip -o -4 addr show` and pick the best LAN address, filtering out
/// virtual / VPN / cellular interfaces that the phone cannot reach.
/// Only returns RFC 1918 private IPs — proxy Fake-IP ranges (198.18.0.0/15)
/// are excluded because they're not directly reachable from the phone.
fn ip_addr_local_ip() -> Option<String> {
    let output = std::process::Command::new("ip")
        .args(["-o", "-4", "addr", "show"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&output.stdout);

    // Collect non-loopback IPv4 addresses with their interface name.
    let mut candidates: Vec<(&str, String)> = Vec::new();
    for line in stdout.lines() {
        let cols: Vec<&str> = line.split_whitespace().collect();
        // Format: "2  wlan2    inet 10.14.164.149/24 ..."
        let iface = cols.get(1)?;
        let ip = cols.get(3)?.split('/').next()?;
        if ip.starts_with("127.") {
            continue;
        }
        candidates.push((iface, ip.to_string()));
    }

    // Priority ranking — only RFC 1918 private IPs are considered safe.
    let mut preferred_private = None; // wlan/eth + private
    let mut any_private = None;       // non-virtual + private
    for (iface, ip) in &candidates {
        let is_preferred = iface.starts_with("wlan")
            || iface.starts_with("eth")
            || iface.starts_with("enp")
            || iface.starts_with("enx")
            || iface.starts_with("wlp");
        let is_virtual = VIRTUAL_PREFIXES.iter().any(|p| iface.starts_with(p));
        let is_private = is_rfc1918_private(ip);

        if is_preferred && is_private && preferred_private.is_none() {
            preferred_private = Some(ip.clone());
        }
        if !is_virtual && is_private && any_private.is_none() {
            any_private = Some(ip.clone());
        }
    }

    preferred_private.or(any_private)
}

/// Fast local IP detection via UDP socket connect (no traffic sent).
/// Queries the kernel routing table — reflects the actual network configuration
/// including proxy adapters and VPN tunnels.
fn udp_local_ip_fast() -> Option<String> {
    use std::net::UdpSocket;
    let sock = UdpSocket::bind("0.0.0.0:0").ok()?;
    sock.connect("8.8.8.8:80").ok()?;
    sock.local_addr().ok().map(|a| a.ip().to_string())
}

/// Generate QR code as SVG
pub fn generate_qr_svg(url: &str) -> String {
    use qrcode::QrCode;
    use qrcode::render::svg;

    let code = QrCode::new(url.as_bytes()).unwrap();
    code.render::<svg::Color>()
        .min_dimensions(200, 200)
        .build()
}

/// Start the HTTP + WebSocket server
pub async fn start_server(
    port: u16,
    state: Arc<ServerState>,
    mut stop_rx: broadcast::Receiver<()>,
) -> Result<()> {
    let frontend = state.frontend_dir.clone();
    let embedded = embedded_frontend();

    let app = Router::new()
        .route("/ws", get(ws_handler))
        .fallback(move |req: axum::http::Request<axum::body::Body>| {
            let frontend = frontend.clone();
            let embedded = embedded.clone();
            async move {
                let path = req.uri().path().trim_start_matches('/');
                let path = if path.is_empty() { "index.html" } else { path };

                // Try embedded files first (works in packaged app)
                if let Some(file) = embedded.get(path) {
                    return axum::response::Response::builder()
                        .header("content-type", file.mime)
                        .body(axum::body::Body::from(file.content))
                        .unwrap();
                }

                // Fallback to filesystem (dev mode)
                let file_path = frontend.join(path);
                let file_path = match file_path.canonicalize() {
                    Ok(p) => p,
                    Err(_) => {
                        return axum::response::Response::builder()
                            .status(404)
                            .body(axum::body::Body::from("Not found"))
                            .unwrap();
                    }
                };
                if !file_path.starts_with(frontend.canonicalize().as_deref().unwrap_or(&frontend)) {
                    return axum::response::Response::builder()
                        .status(403)
                        .body(axum::body::Body::from("Forbidden"))
                        .unwrap();
                }

                match tokio::fs::read(&file_path).await {
                    Ok(data) => {
                        let mime = match file_path.extension().and_then(|e| e.to_str()) {
                            Some("html") => "text/html; charset=utf-8",
                            Some("css") => "text/css; charset=utf-8",
                            Some("js") => "application/javascript; charset=utf-8",
                            Some("png") => "image/png",
                            Some("svg") => "image/svg+xml",
                            Some("json") => "application/json",
                            _ => "application/octet-stream",
                        };
                        axum::response::Response::builder()
                            .header("content-type", mime)
                            .body(axum::body::Body::from(data))
                            .unwrap()
                    }
                    Err(_) => axum::response::Response::builder()
                        .status(404)
                        .body(axum::body::Body::from("Not found"))
                        .unwrap(),
                }
            }
        })
        .with_state(state.clone());

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = TcpListener::bind(addr).await?;
    info!("Server listening on {}", addr);

    // Start background IME state monitor (polls every 200ms, pushes on change)
    tokio::spawn(state.clone().run_ime_monitor());

    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(async move {
            let _ = stop_rx.recv().await;
            info!("Server shutting down");
        })
        .await?;

    Ok(())
}

/// WebSocket upgrade handler
async fn ws_handler(
    ws: WebSocketUpgrade,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    headers: HeaderMap,
    AxumState(state): AxumState<Arc<ServerState>>,
) -> impl IntoResponse {
    let device_name = parse_device_name(&headers);
    ws.on_upgrade(move |socket| handle_ws(socket, state, addr, device_name))
}

/// Extract a friendly device name from User-Agent
fn parse_device_name(headers: &HeaderMap) -> String {
    let ua = headers.get("user-agent")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("Unknown Device");

    if ua.contains("iPhone") { "iPhone".to_string() }
    else if ua.contains("iPad") { "iPad".to_string() }
    else if ua.contains("Android") { "Android".to_string() }
    else if ua.contains("Windows") { "Windows".to_string() }
    else if ua.contains("Macintosh") || ua.contains("Mac OS") { "Mac".to_string() }
    else if ua.contains("Linux") { "Linux".to_string() }
    else { "设备".to_string() }
}

/// Handle a single WebSocket connection
async fn handle_ws(socket: WebSocket, state: Arc<ServerState>, addr: SocketAddr, device_name: String) {
    let addr_str = format!("{}", addr);
    info!("Client connected: {} ({})", addr_str, device_name);

    // Track this device as "connecting" (before auth)
    *state.connecting_addr.lock().await = Some(addr);

    // Split socket into sink (for sending) and stream (for receiving)
    let (mut ws_sink, mut ws_stream) = socket.split();

    // Create an unbounded channel for sending messages to this WebSocket
    let (tx, mut rx) = mpsc::unbounded_channel::<Message>();

    // Task: forward channel messages → WebSocket
    let forward_task = tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            if ws_sink.send(msg).await.is_err() {
                break;
            }
        }
    });

    // Step 1: Require PIN authentication
    let auth_msg = serde_json::to_string(&ServerMsg::AuthRequired).unwrap();
    let _ = tx.send(Message::Text(auth_msg.into()));

    // Notify GUI: a device is connecting (QR → PIN transition)
    state.emit_gui_event("device-connecting", serde_json::json!({
        "device_name": device_name,
    }));

    let authenticated = loop {
        match ws_stream.next().await {
            Some(Ok(Message::Text(text))) => {
                let text_str: &str = text.as_ref();
                if let Ok(ClientMsg::Auth { pin }) = serde_json::from_str(text_str) {
                    let current_pin = state.pin.lock().await.clone();
                    if pin == current_pin {
                        info!("{} authenticated", addr_str);
                        *state.pin.lock().await = generate_pin();
                        break true;
                    } else {
                        warn!("{} auth failed (wrong PIN)", addr_str);
                        let fail = serde_json::to_string(&ServerMsg::AuthFail).unwrap();
                        let _ = tx.send(Message::Text(fail.into()));
                    }
                }
            }
            // Connection closed, error, or non-text message → device left
            _ => break false,
        }
    };

    if !authenticated {
        // Clear connecting_addr since this device is leaving
        {
            let mut connecting = state.connecting_addr.lock().await;
            if *connecting == Some(addr) {
                *connecting = None;
                // Notify GUI: connecting device left without auth
                state.emit_gui_event("device-connecting-cancelled", serde_json::json!({}));
            }
        }
        let _ = tx.send(Message::Close(Some(axum::extract::ws::CloseFrame {
            code: 4003,
            reason: "auth failed".into(),
        })));
        forward_task.abort();
        return;
    }

    // Check if there's already an active controller
    let has_active = state.active_ws.lock().await.is_some();

    if !has_active {
        // No active controller → take control immediately
        *state.active_ws.lock().await = Some((addr, tx.clone()));
        *state.connected_device.lock().await = Some(device_name.clone());
        *state.connecting_addr.lock().await = None; // no longer "connecting"
        let proot = if is_proot() { Some(true) } else { None };
        let msg = serde_json::to_string(&ServerMsg::CtrlOk { proot }).unwrap();
        let _ = tx.send(Message::Text(msg.into()));
        state.send_event(format!("✅ {} ({}) 已连接", device_name, addr_str));
        info!("{} is now controller", addr_str);
        // Push initial IME status to the new controller
        state.push_ime_status().await;
        // Notify GUI: device authenticated (PIN → STOP transition)
        state.emit_gui_event("device-authenticated", serde_json::json!({
            "device_name": device_name,
        }));
    } else {
        // Active controller exists → need approval
        let has_pending = state.pending_ws.lock().await.is_some();
        if has_pending {
            let msg = serde_json::to_string(&ServerMsg::Wait {
                reason: Some("busy".into())
            }).unwrap();
            let _ = tx.send(Message::Text(msg.into()));
            let _ = tx.send(Message::Close(Some(axum::extract::ws::CloseFrame {
                code: 4002,
                reason: "busy".into(),
            })));
            forward_task.abort();
            return;
        }

        *state.pending_ws.lock().await = Some(addr);

        let (approval_tx, approval_rx) = oneshot::channel::<String>();
        *state.approval_tx.lock().await = Some(approval_tx);

        // Send approval request DIRECTLY to the active controller's WebSocket
        let req_msg = serde_json::json!({"a": "approval_req", "ip": addr_str}).to_string();
        state.send_to_active(&req_msg).await;

        // Notify new client they're waiting
        let msg = serde_json::to_string(&ServerMsg::Wait { reason: None }).unwrap();
        let _ = tx.send(Message::Text(msg.into()));
        state.send_event(format!("⏳ {} 等待审批", addr_str));

        // Wait for approval with timeout
        let result = tokio::time::timeout(
            tokio::time::Duration::from_secs(30),
            approval_rx,
        ).await;

        match result {
            Ok(Ok(response)) if response == "accept" => {
                // Kick old controller
                let kick = serde_json::json!({"a": "wait", "reason": "kicked"}).to_string();
                state.send_to_active(&kick).await;
                // Close old controller's WebSocket
                if let Some((_, old_tx)) = state.active_ws.lock().await.take() {
                    let _ = old_tx.send(Message::Close(Some(axum::extract::ws::CloseFrame {
                        code: 4001,
                        reason: "new controller".into(),
                    })));
                }

                // Promote pending to active
                *state.active_ws.lock().await = Some((addr, tx.clone()));
                *state.connected_device.lock().await = Some(device_name.clone());
                *state.pending_ws.lock().await = None;
                *state.approval_tx.lock().await = None;
                *state.connecting_addr.lock().await = None;

                let proot = if is_proot() { Some(true) } else { None };
                let msg = serde_json::to_string(&ServerMsg::CtrlOk { proot }).unwrap();
                let _ = tx.send(Message::Text(msg.into()));
                state.send_event(format!("✅ {} ({}) 已接管控制", device_name, addr_str));
                info!("{} approved, now controller", addr_str);
                // Push initial IME status to the new controller
                state.push_ime_status().await;
                // Notify GUI: device authenticated (PIN → STOP transition)
                state.emit_gui_event("device-authenticated", serde_json::json!({
                    "device_name": device_name,
                }));
            }
            _ => {
                let reason = match result {
                    Ok(Ok(r)) if r == "reject" => "rejected".to_string(),
                    Ok(Ok(r)) => r,
                    _ => "timeout".to_string(),
                };
                // Send rejection message while socket is still open
                let msg = serde_json::to_string(&ServerMsg::Wait {
                    reason: Some(reason.clone())
                }).unwrap();
                let _ = tx.send(Message::Text(msg.into()));
                // Give frontend time to process the message before closing
                tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                let _ = tx.send(Message::Close(Some(axum::extract::ws::CloseFrame {
                    code: 4002,
                    reason: reason.clone().into(),
                })));

                *state.pending_ws.lock().await = None;
                *state.approval_tx.lock().await = None;
                state.send_event(format!("🚫 {} {}", addr_str,
                    if reason == "timeout" { "等待超时" } else { "被拒绝" }));
                forward_task.abort();
                return;
            }
        }
    }

    // Message loop for the active controller
    while let Some(Ok(msg)) = ws_stream.next().await {
        match msg {
            Message::Text(text) => {
                let text_str: &str = text.as_ref();
                match serde_json::from_str::<ClientMsg>(text_str) {
                    Ok(client_msg) => {
                        handle_client_msg(client_msg, &state, &addr_str).await;
                    }
                    Err(e) => {
                        warn!("Invalid message from {}: {}", addr_str, e);
                    }
                }
            }
            Message::Binary(data) => {
                if let Some(client_msg) = ClientMessage::from_binary(&data) {
                    handle_binary_msg(client_msg, &state, &addr_str).await;
                } else {
                    warn!("Invalid binary frame from {}", addr_str);
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    // Cleanup on disconnect
    let was_active = {
        let mut active = state.active_ws.lock().await;
        let was = active.as_ref().map(|(a, _)| *a) == Some(addr);
        if was {
            *active = None;
            *state.connected_device.lock().await = None;
        }
        was
    };

    // Check if this was a connecting device (scanned QR but didn't authenticate)
    let was_connecting = {
        let mut connecting = state.connecting_addr.lock().await;
        let was = *connecting == Some(addr);
        if was { *connecting = None; }
        was
    };

    let mut pending = state.pending_ws.lock().await;
    if *pending == Some(addr) {
        *pending = None;
        let mut tx_lock = state.approval_tx.lock().await;
        if let Some(approval_sender) = tx_lock.take() {
            let _ = approval_sender.send("timeout".to_string());
        }
    }

    state.send_event(format!("❌ {} 已断开", addr_str));
    info!("Client disconnected: {}", addr_str);

    // Destroy virtual gamepad when controller disconnects
    {
        let mut gp = state.gamepad.lock().await;
        gp.destroy();
    }

    if was_active {
        // Active controller disconnected → STOP → START
        state.emit_gui_event("device-disconnected", serde_json::json!({
            "device_name": device_name,
        }));
    } else if was_connecting {
        // Device scanned QR but left without entering PIN → QR → START
        state.emit_gui_event("device-connecting-cancelled", serde_json::json!({}));
    }

    forward_task.abort();
}

/// Handle a parsed client message
async fn handle_client_msg(msg: ClientMsg, state: &Arc<ServerState>, addr: &str) {
    let input = state.input.lock().await;

    let result = match msg {
        ClientMsg::Move { x, y } => input.mouse_move(x, y).await,
        ClientMsg::Click { b } => input.mouse_click(b).await,
        ClientMsg::DoubleClick => input.mouse_double_click().await,
        ClientMsg::MouseDown { b } => input.mouse_down(b).await,
        ClientMsg::MouseUp { b } => input.mouse_up(b).await,
        ClientMsg::Scroll { x, y } => input.mouse_scroll(x, y).await,
        ClientMsg::PinchZoom { m } => input.mouse_zoom(m).await,
        ClientMsg::TypeText { t } => {
            info!("typing {} chars from {}: {:?}", t.len(), addr, t);
            input.type_text(&t).await
        }
        ClientMsg::Key { k } => input.send_key(&k).await,
        ClientMsg::KeyPress { k } => input.press_key(&k).await,
        ClientMsg::Backspace { n } => {
            for _ in 0..n {
                if let Err(e) = input.send_key("Backspace").await {
                    warn!("Backspace error: {}", e);
                    break;
                }
            }
            return;
        }
        ClientMsg::ToggleIME { mode } => {
            // Legacy handler: directly set IME state via platform
            let want_zh = mode == "zh";
            info!("ToggleIME (legacy): mode={}", mode);
            // Toggle to match desired state by reading current and toggling if needed
            let current = state.platform.get_ime_status();
            let need_toggle = (want_zh && current != "ZH") || (!want_zh && current != "EN");
            if need_toggle {
                state.platform.toggle_ime(state.ime_toggle_key.as_deref());
                // Wait for the OS/IME to process the simulated key event
                tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;
            }
            // Push updated status
            state.push_ime_status().await;
            return;
        }
        ClientMsg::PressImeToggle => {
            // Physical IME toggle: simulate platform key press
            info!("PressImeToggle from {}", addr);
            drop(input);
            state.platform.toggle_ime(state.ime_toggle_key.as_deref());
            // Wait for the OS/IME to process the simulated key event
            // 50ms is too fast for some IMEs — they haven't updated their state yet
            tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;
            // Push updated status
            state.push_ime_status().await;
            return;
        }
        ClientMsg::RefreshIme => {
            // Client requests current IME status (passive calibration)
            info!("RefreshIme from {}", addr);
            drop(input);
            state.push_ime_status().await;
            return;
        }
        ClientMsg::ApprovalResp { r } => {
            drop(input);
            let mut tx_lock = state.approval_tx.lock().await;
            if let Some(tx) = tx_lock.take() {
                let _ = tx.send(r.clone());
                info!("Approval response: {}", r);
            }
            return;
        }
        ClientMsg::Auth { .. } => {
            // Auth handled in connection setup, ignore here
            return;
        }
        ClientMsg::VigemCheck => {
            let installed = GamepadManager::is_installed();
            info!("ViGEm check from {}: installed={}", addr, installed);
            let msg = serde_json::json!({"a": "vigem", "installed": installed}).to_string();
            drop(input);
            state.send_to_active(&msg).await;
            return;
        }
        ClientMsg::GamepadConnect { t } => {
            info!("Gamepad connect from {}: type={}", addr, t);
            drop(input);
            let mut gp = state.gamepad.lock().await;
            let result = match t.as_str() {
                "xbox" => gp.create_xbox(),
                "ps" => gp.create_ds4(),
                _ => {
                    warn!("Unknown gamepad type: {}", t);
                    return;
                }
            };
            if let Err(e) = result {
                warn!("Failed to create gamepad: {}", e);
            }
            return;
        }
        ClientMsg::GamepadState { lx, ly, rx, ry, lt, rt, b } => {
            let mut gp = state.gamepad.lock().await;
            if let Err(e) = gp.update(lx, ly, rx, ry, lt, rt, b) {
                // Only log occasionally to avoid spam
                if rand::random::<u8>() < 5 {
                    warn!("Gamepad update error: {}", e);
                }
            }
            return;
        }
        ClientMsg::GamepadDisconnect => {
            info!("Gamepad disconnect from {}", addr);
            drop(input);
            let mut gp = state.gamepad.lock().await;
            gp.destroy();
            return;
        }
    };

    if let Err(e) = result {
        warn!("Input error from {}: {}", addr, e);
    }
}

/// Handle a binary TLV message (gamepad state, input move/scroll, heartbeat)
async fn handle_binary_msg(msg: ClientMessage, state: &Arc<ServerState>, addr: &str) {
    match msg {
        ClientMessage::BinaryGamepad(gp) => {
            let (lx, ly, rx, ry, lt, rt, buttons) = gp.to_f64();
            let mut gp_mgr = state.gamepad.lock().await;
            if let Err(e) = gp_mgr.update(lx, ly, rx, ry, lt, rt, buttons) {
                // Only log occasionally to avoid spam
                if rand::random::<u8>() < 5 {
                    warn!("Gamepad binary update error from {}: {}", addr, e);
                }
            }
        }
        ClientMessage::BinaryMove { x, y } => {
            let input = state.input.lock().await;
            if let Err(e) = input.mouse_move(x as f64, y as f64).await {
                if rand::random::<u8>() < 5 {
                    warn!("Binary move error from {}: {}", addr, e);
                }
            }
        }
        ClientMessage::BinaryScroll { x, y } => {
            let input = state.input.lock().await;
            if let Err(e) = input.mouse_scroll(x as f64, y as f64).await {
                if rand::random::<u8>() < 5 {
                    warn!("Binary scroll error from {}: {}", addr, e);
                }
            }
        }
        ClientMessage::Heartbeat => {
            // Heartbeat received, no action needed
        }
        ClientMessage::Json(_) => {
            // Should not reach here — JSON messages go through handle_client_msg
            warn!("Unexpected Json in handle_binary_msg from {}", addr);
        }
    }
}

/// 统一消息分发入口（供 USB/BLE 等非 WebSocket 通道调用）
pub async fn handle_client_message_static(
    msg: ClientMessage,
    state: &Arc<ServerState>,
    addr: &str,
) {
    match msg {
        ClientMessage::Json(json_msg) => {
            handle_client_msg(json_msg, state, addr).await;
        }
        other => {
            handle_binary_msg(other, state, addr).await;
        }
    }
}
