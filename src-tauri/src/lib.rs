use std::path::PathBuf;
use std::sync::Arc;
use tauri::{Manager, State};
use tokio::sync::{broadcast, Mutex};
use serde::Serialize;

mod ble;
mod codec;
mod config;
mod gamepad;
mod input;
mod platform;
mod protocol;
mod server;
mod usb;

use config::AppConfig;
use server::ServerState;

/// Tauri-managed app state
pub struct AppState {
    server_state: Option<Arc<ServerState>>,
    stop_tx: Option<broadcast::Sender<()>>,
    server_handle: Option<tokio::task::JoinHandle<()>>,
    port: u16,
    running: bool,
    config_path: PathBuf,
    config: AppConfig,
}

#[derive(Serialize)]
pub struct ServerStatus {
    pub running: bool,
    pub ip: String,
    pub port: u16,
    pub url: String,
    pub qr_svg: String,
    pub events: Vec<String>,
    pub device_name: Option<String>,
    pub pin: Option<String>,
}

// ─── Tauri Commands ────────────────────────────────────────

#[tauri::command]
async fn get_status(state: State<'_, Mutex<AppState>>) -> Result<ServerStatus, String> {
    let app = state.lock().await;
    let ip = server::get_local_ip();
    let url = format!("http://{}:{}", ip, app.port);
    let qr_svg = server::generate_qr_svg(&url);

    let device_name = if let Some(ref ss) = app.server_state {
        ss.connected_device.lock().await.clone()
    } else {
        None
    };

    let pin = if let Some(ref ss) = app.server_state {
        Some(ss.pin.lock().await.clone())
    } else {
        None
    };

    Ok(ServerStatus {
        running: app.running,
        ip,
        port: app.port,
        url,
        qr_svg,
        events: Vec::new(),
        device_name,
        pin,
    })
}

#[tauri::command]
async fn start_server_cmd(
    port: u16,
    state: State<'_, Mutex<AppState>>,
    app_handle: tauri::AppHandle,
) -> Result<ServerStatus, String> {
    let mut app = state.lock().await;
    if app.running {
        return Err("Server already running".into());
    }

    let input_sim = match input::InputSimulator::new().await {
        Ok(sim) => sim,
        Err(e) => {
            tracing::warn!("InputSimulator init failed (will retry on first input): {}", e);
            input::InputSimulator::new_lazy()
        }
    };

    let frontend_dir: PathBuf = app_handle
        .path()
        .resource_dir()
        .unwrap_or_else(|_| PathBuf::from("."))
        .join("frontend");

    // Fallback: check relative to binary
    let frontend_dir = if frontend_dir.join("index.html").exists() {
        frontend_dir
    } else {
        // Try relative to the executable
        let exe_dir = std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|p| p.to_path_buf()))
            .unwrap_or_default();
        // Try: exe_dir/frontend, exe_dir/../frontend, cwd/frontend, cwd/../frontend
        let candidates = [
            exe_dir.join("frontend"),
            exe_dir.join("..").join("frontend"),
            std::env::current_dir().unwrap_or_default().join("frontend"),
            std::env::current_dir().unwrap_or_default().join("..").join("frontend"),
        ];
        let found = candidates.iter().find(|c| c.join("index.html").exists());
        if let Some(dir) = found {
            dir.clone()
        } else {
            PathBuf::from("frontend")
        }
    };

    let server_state = Arc::new(ServerState::new(
        input_sim,
        frontend_dir,
        app.config.ime_toggle_key.clone(),
        Some(app_handle.clone()),
    ));
    let (stop_tx, stop_rx) = broadcast::channel(1);

    let state_clone = server_state.clone();
    let port_clone = port;

    // Start server in background
    let server_handle = tokio::spawn(async move {
        if let Err(e) = server::start_server(port_clone, state_clone, stop_rx).await {
            tracing::error!("Server error: {}", e);
        }
    });

    // Start USB AOA listener in background
    let usb_state = server_state.clone();
    let usb_stop_rx = stop_tx.subscribe();
    let _usb_handle = tokio::spawn(async move {
        usb::start_usb_listener(usb_state, usb_stop_rx).await;
    });

    // Start BLE GATT Server in background
    let ble_state = server_state.clone();
    let ble_stop_rx = stop_tx.subscribe();
    let _ble_handle = tokio::spawn(async move {
        ble::start_ble_server(ble_state, ble_stop_rx).await;
    });

    let ip = server::get_local_ip();
    let url = format!("http://{}:{}", ip, port);
    let qr_svg = server::generate_qr_svg(&url);
    let pin = server_state.pin.lock().await.clone();

    app.server_state = Some(server_state);
    app.stop_tx = Some(stop_tx);
    app.server_handle = Some(server_handle);
    app.port = port;
    app.running = true;

    Ok(ServerStatus {
        running: true,
        ip,
        port,
        url,
        qr_svg,
        events: Vec::new(),
        device_name: None,
        pin: Some(pin),
    })
}

#[tauri::command]
async fn stop_server_cmd(state: State<'_, Mutex<AppState>>) -> Result<(), String> {
    let mut app = state.lock().await;
    if !app.running {
        return Err("Server not running".into());
    }

    // Close active WebSocket connection first
    if let Some(ref ss) = app.server_state {
        if let Some((_, tx)) = ss.active_ws.lock().await.take() {
            let _ = tx.send(axum::extract::ws::Message::Close(Some(axum::extract::ws::CloseFrame {
                code: 1000,
                reason: "server stopped".into(),
            })));
        }
        *ss.connected_device.lock().await = None;
    }

    if let Some(tx) = app.stop_tx.take() {
        let _ = tx.send(());
    }

    // Wait for server task to finish (releases the port)
    if let Some(handle) = app.server_handle.take() {
        drop(app); // release the lock while waiting
        let _ = tokio::time::timeout(
            tokio::time::Duration::from_secs(3),
            handle,
        ).await;
        // Re-acquire lock to finish cleanup
        let mut app = state.lock().await;
        if let Some(server_state) = app.server_state.take() {
            server_state.input.lock().await.close().await;
        }
        app.running = false;
        return Ok(());
    }

    // Close input simulator
    if let Some(server_state) = app.server_state.take() {
        server_state.input.lock().await.close().await;
    }

    app.running = false;
    Ok(())
}

// ─── IME Config Commands ──────────────────────────────────

#[derive(Serialize)]
struct ImeConfigResponse {
    ime_toggle_key: Option<String>,
}

#[tauri::command]
async fn get_ime_config(state: State<'_, Mutex<AppState>>) -> Result<ImeConfigResponse, String> {
    let app = state.lock().await;
    Ok(ImeConfigResponse {
        ime_toggle_key: app.config.ime_toggle_key.clone(),
    })
}

#[tauri::command]
async fn save_ime_config(
    ime_toggle_key: Option<String>,
    state: State<'_, Mutex<AppState>>,
) -> Result<(), String> {
    let mut app = state.lock().await;
    app.config.ime_toggle_key = ime_toggle_key.clone();
    config::save_config(&app.config_path, &app.config)?;
    // If server is running, the new config takes effect on next server start
    if app.server_state.is_some() {
        tracing::info!("IME toggle key saved: {:?} (takes effect on next server start)", ime_toggle_key);
    }
    Ok(())
}

// ─── New Commands ─────────────────────────────────────────

/// Check if a port is available for binding
#[tauri::command]
async fn check_port(port: u16) -> Result<bool, String> {
    match tokio::net::TcpListener::bind(format!("0.0.0.0:{}", port)).await {
        Ok(_) => Ok(true),   // port available
        Err(_) => Ok(false), // port in use
    }
}

/// Get the application version string
#[tauri::command]
fn app_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Check if ViGEmBus driver is installed
#[tauri::command]
fn check_vigem_installed() -> bool {
    gamepad::GamepadManager::is_installed()
}

/// Check if USB driver (libusb) is available and can open AOA devices
#[tauri::command]
fn check_usb_driver() -> bool {
    usb::check_usb_driver()
}

/// USB 诊断：枚举所有 USB 设备，返回诊断信息
#[tauri::command]
fn diagnose_usb() -> String {
    usb::diagnose_usb()
}

/// Get whether autostart on boot is enabled
#[tauri::command]
fn get_autostart(app: tauri::AppHandle) -> bool {
    use tauri_plugin_autostart::AutoLaunchManager;
    if let Some(manager) = app.try_state::<AutoLaunchManager>() {
        manager.is_enabled().unwrap_or(false)
    } else {
        false
    }
}

/// Toggle autostart on boot
#[tauri::command]
fn set_autostart(app: tauri::AppHandle, enable: bool) -> Result<(), String> {
    use tauri_plugin_autostart::AutoLaunchManager;
    let manager = app.try_state::<AutoLaunchManager>()
        .ok_or("Autostart plugin not initialized")?;
    if enable {
        manager.enable().map_err(|e| format!("Failed to enable autostart: {}", e))?;
    } else {
        manager.disable().map_err(|e| format!("Failed to disable autostart: {}", e))?;
    }
    Ok(())
}

/// Get minimize-to-tray setting
#[tauri::command]
fn get_minimize_to_tray(state: State<'_, Mutex<AppState>>) -> bool {
    state.blocking_lock().config.minimize_to_tray
}

/// Set minimize-to-tray setting
#[tauri::command]
fn set_minimize_to_tray(state: State<'_, Mutex<AppState>>, enable: bool) -> Result<(), String> {
    let mut s = state.blocking_lock();
    s.config.minimize_to_tray = enable;
    config::save_config(&s.config_path, &s.config)
}

// ─── Tauri App Setup ──────────────────────────────────────

pub fn run() {
    tracing_subscriber::fmt::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .setup(|app| {
            let config_path = app.path().app_config_dir()
                .unwrap_or_else(|_| PathBuf::from("."));
            let loaded_config = config::load_config(&config_path);
            app.manage(Mutex::new(AppState {
                server_state: None,
                stop_tx: None,
                server_handle: None,
                port: 8765,
                running: false,
                config_path,
                config: loaded_config,
            }));

            // ── System Tray ──────────────────────────────
            use tauri::menu::{MenuBuilder, MenuItemBuilder};
            use tauri::tray::{TrayIconBuilder, TrayIconEvent, MouseButton, MouseButtonState};

            let show_item = MenuItemBuilder::with_id("show", "显示窗口").build(app)?;
            let quit_item = MenuItemBuilder::with_id("quit", "退出").build(app)?;
            let menu = MenuBuilder::new(app)
                .items(&[&show_item, &quit_item])
                .build()?;

            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .tooltip("NexusPad")
                .on_menu_event(|app, event| {
                    match event.id().as_ref() {
                        "show" => {
                            if let Some(win) = app.get_webview_window("main") {
                                let _ = win.show();
                                let _ = win.set_focus();
                            }
                        }
                        "quit" => {
                            app.exit(0);
                        }
                        _ => {}
                    }
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(win) = app.get_webview_window("main") {
                            let _ = win.show();
                            let _ = win.set_focus();
                        }
                    }
                })
                .build(app)?;

            // ── Close-to-tray: intercept window close ────
            let window = app.get_webview_window("main").unwrap();
            let window_clone = window.clone();
            let app_handle = app.handle().clone();
            window.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                    // Check minimize_to_tray setting
                    let minimize = if let Some(state) = app_handle.try_state::<tokio::sync::Mutex<AppState>>() {
                        state.blocking_lock().config.minimize_to_tray
                    } else {
                        true // default: minimize to tray
                    };
                    if minimize {
                        api.prevent_close();
                        let _ = window_clone.hide();
                    }
                    // If minimize_to_tray is false, allow close (app exits)
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            start_server_cmd,
            stop_server_cmd,
            get_ime_config,
            save_ime_config,
            check_port,
            app_version,
            check_vigem_installed,
            check_usb_driver,
            diagnose_usb,
            get_autostart,
            set_autostart,
            get_minimize_to_tray,
            set_minimize_to_tray,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

/// CLI mode: start server without Tauri GUI
pub fn run_cli() {
    tracing_subscriber::fmt::init();
    let args: Vec<String> = std::env::args().collect();
    let port: u16 = args.windows(2)
        .find(|w| w[0] == "--port")
        .and_then(|w| w[1].parse().ok())
        .unwrap_or(8765);
    let ime_key_arg: Option<String> = args.windows(2)
        .find(|w| w[0] == "--ime-key")
        .map(|w| w[1].clone());

    // Load config from exe directory, override with --ime-key if provided
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_default();
    let mut app_config = config::load_config(&exe_dir);
    if let Some(key) = ime_key_arg {
        app_config.ime_toggle_key = Some(key);
    }

    let rt = tokio::runtime::Runtime::new().expect("Failed to create tokio runtime");
    rt.block_on(async {
        let input_sim = match input::InputSimulator::new().await {
            Ok(sim) => {
                eprintln!("[ok] InputSimulator ready");
                sim
            }
            Err(e) => {
                eprintln!("[warn] InputSimulator failed: {}", e);
                input::InputSimulator::new_lazy()
            }
        };

        let frontend_dir = exe_dir.clone();
        let ime_toggle_key = app_config.ime_toggle_key.clone();
        let server_state = Arc::new(server::ServerState::new(input_sim, frontend_dir, ime_toggle_key, None));
        let pin = server_state.pin.lock().await.clone();
        let local_ip = server::get_local_ip();
        let url = format!("http://{}:{}", local_ip, port);

        eprintln!("[info] Local IP: {}", local_ip);
        eprintln!("[info] Port: {}", port);
        eprintln!("[info] PIN: {}", pin);
        eprintln!("[info] URL: {}", url);
        if let Some(ref key) = app_config.ime_toggle_key {
            eprintln!("[info] IME toggle key: {}", key);
        }

        let (stop_tx, stop_rx) = tokio::sync::broadcast::channel(1);
        let state_clone = server_state.clone();

        let server_handle = tokio::spawn(async move {
            match server::start_server(port, state_clone, stop_rx).await {
                Ok(()) => eprintln!("[info] Server exited normally"),
                Err(e) => eprintln!("[error] Server error: {}", e),
            }
        });

        // Start USB AOA listener
        let usb_state = server_state.clone();
        let usb_stop_rx = stop_tx.subscribe();
        tokio::spawn(async move {
            usb::start_usb_listener(usb_state, usb_stop_rx).await;
        });

        // Give server a moment to start
        tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;

        eprintln!("[ok] Server running on port {}", port);
        eprintln!("Open {} in phone browser", url);
        eprintln!("PIN: {}", pin);
        eprintln!("Press Ctrl+C to stop");

        // Wait for Ctrl+C
        let _ = tokio::signal::ctrl_c().await;

        eprintln!("Stopping...");
        let _ = stop_tx.send(());
        let _ = tokio::time::timeout(tokio::time::Duration::from_secs(2), server_handle).await;
        eprintln!("Stopped.");
    });
}
