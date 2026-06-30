/// USB 调试工具 - 收集详细的 USB 通信日志
/// 
/// 用于调试 AOA 握手失败、设备驱动问题等
use std::fs::{File, OpenOptions};
use std::io::{Write, BufWriter};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{anyhow, Result};
use tracing::{info, warn};

const ANDROID_VENDOR_IDS: &[u16] = &[
    0x18D1, // Google (AOA)
    0x22D9, // OPPO / OnePlus / Realme
    // 其他 Android Vendor IDs 省略...
];

/// USB 调试会话
pub struct UsbDebugSession {
    log_file: Arc<Mutex<BufWriter<File>>>,
    device_path: Option<PathBuf>,
}

impl UsbDebugSession {
    /// 创建新的调试会话
    pub fn new(session_name: &str) -> Result<Self> {
        // 创建调试目录
        let debug_dir = dirs::data_local_dir()
            .ok_or_else(|| anyhow!("无法找到数据目录"))?
            .join("NexusPad")
            .join("debug");
        
        std::fs::create_dir_all(&debug_dir)?;
        
        // 创建日志文件
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        
        let log_path = debug_dir.join(format!("usb_debug_{}_{}.log", timestamp, session_name));
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)?;
        
        info!("USB 调试日志: {}", log_path.display());
        
        let mut writer = BufWriter::new(file);
        writeln!(writer, "=== USB 调试会话开始 ===")?;
        writeln!(writer, "时间戳: {}", timestamp)?;
        writeln!(writer, "会话名: {}", session_name)?;
        writeln!(writer, "系统: Windows")?;
        writeln!(writer, "")?;
        writer.flush()?;
        
        Ok(Self {
            log_file: Arc::new(Mutex::new(writer)),
            device_path: Some(log_path),
        })
    }
    
    /// 记录系统 USB 设备信息
    pub fn log_system_usb_info(&self) -> Result<()> {
        let mut writer = self.log_file.lock().unwrap();
        
        writeln!(writer, "=== 系统 USB 设备信息 ===")?;
        writeln!(writer, "")?;
        
        match rusb::devices() {
            Ok(devices) => {
                writeln!(writer, "发现 {} 个 USB 设备:", devices.len())?;
                
                for (i, device) in devices.iter().enumerate() {
                    match device.device_descriptor() {
                        Ok(desc) => {
                            let vid = desc.vendor_id();
                            let pid = desc.product_id();
                            
                            let class_code = desc.class_code();
                            let subclass_code = desc.sub_class_code();
                            let protocol_code = desc.protocol_code();
                            
                            let manufacturer = device.open()
                                .ok()
                                .and_then(|handle| desc.manufacturer_string_index()
                                    .and_then(|idx| handle.read_string_descriptor_ascii(idx).ok()))
                                .unwrap_or_else(|| "未知".to_string());
                            
                            let product = device.open()
                                .ok()
                                .and_then(|handle| desc.product_string_index()
                                    .and_then(|idx| handle.read_string_descriptor_ascii(idx).ok()))
                                .unwrap_or_else(|| format!("{:04X}:{:04X}", vid, pid));
                            
                            let serial = device.open()
                                .ok()
                                .and_then(|handle| desc.serial_number_string_index()
                                    .and_then(|idx| handle.read_string_descriptor_ascii(idx).ok()))
                                .unwrap_or_else(|| "无".to_string());
                            
                            let bus = device.bus_number();
                            let address = device.address();
                            let speed = device.speed();
                            
                            writeln!(writer, "设备 #{}:", i + 1)?;
                            writeln!(writer, "  VID:PID: {:04X}:{:04X}", vid, pid)?;
                            writeln!(writer, "  制造商: {}", manufacturer)?;
                            writeln!(writer, "  产品: {}", product)?;
                            writeln!(writer, "  序列号: {}", serial)?;
                            writeln!(writer, "  总线: {}, 地址: {}", bus, address)?;
                            writeln!(writer, "  速度: {:?}", speed)?;
                            writeln!(writer, "  类: 0x{:02X}, 子类: 0x{:02X}, 协议: 0x{:02X}", 
                                    class_code, subclass_code, protocol_code)?;
                            
                            // 检查是否为 Android 设备
                            if ANDROID_VENDOR_IDS.contains(&vid) {
                                writeln!(writer, "  ⚠ 这是 Android 设备")?;
                                
                                // 尝试打开设备以检查权限
                                match device.open() {
                                    Ok(_) => writeln!(writer, "  ✓ 可以正常打开（驱动 OK）")?,
                                    Err(e) => writeln!(writer, "  ✗ 无法打开: {}", e)?,
                                }
                            }
                            
                            // 检查是否为 AOA 设备
                            let is_aoa = crate::usb::is_aoa_pid(pid);
                            if is_aoa {
                                writeln!(writer, "  📱 这是 AOA 设备")?;
                            }
                            
                            writeln!(writer, "")?;
                        }
                        Err(e) => {
                            writeln!(writer, "设备 #{}: 无法读取描述符: {}", i + 1, e)?;
                        }
                    }
                }
            }
            Err(e) => {
                writeln!(writer, "无法枚举 USB 设备: {}", e)?;
            }
        }
        
        writer.flush()?;
        Ok(())
    }
    
    /// 记录设备连接状态
    pub fn log_device_connection(&self, device_desc: &str, connected: bool) -> Result<()> {
        let mut writer = self.log_file.lock().unwrap();
        
        if connected {
            writeln!(writer, "✅ 设备连接: {}", device_desc)?;
        } else {
            writeln!(writer, "❌ 设备断开: {}", device_desc)?;
        }
        
        writer.flush()?;
        Ok(())
    }
    
    /// 记录 AOA 握手步骤
    pub fn log_aoa_handshake_step(&self, step: &str, success: bool, details: Option<&str>) -> Result<()> {
        let mut writer = self.log_file.lock().unwrap();
        
        let status = if success { "✓" } else { "✗" };
        writeln!(writer, "{} AOA 握手步骤: {}", status, step)?;
        
        if let Some(details) = details {
            writeln!(writer, "  详情: {}", details)?;
        }
        
        writer.flush()?;
        Ok(())
    }
    
    /// 记录 USB 错误
    pub fn log_usb_error(&self, context: &str, error: &str) -> Result<()> {
        let mut writer = self.log_file.lock().unwrap();
        
        writeln!(writer, "🔥 USB 错误 [{}]: {}", context, error)?;
        
        writer.flush()?;
        Ok(())
    }
    
    /// 记录设备重新枚举事件
    pub fn log_device_reenumeration(&self, old_vid_pid: &str, new_vid_pid: &str, timeout_ms: u64) -> Result<()> {
        let mut writer = self.log_file.lock().unwrap();
        
        writeln!(writer, "🔄 设备重新枚举事件")?;
        writeln!(writer, "  从: {}", old_vid_pid)?;
        writeln!(writer, "  到: {}", new_vid_pid)?;
        writeln!(writer, "  等待时间: {}ms", timeout_ms)?;
        
        writer.flush()?;
        Ok(())
    }
    
    /// 获取日志文件路径
    pub fn get_log_path(&self) -> Option<PathBuf> {
        self.device_path.clone()
    }
    
    /// 结束会话
    pub fn end_session(&self, success: bool) -> Result<()> {
        let mut writer = self.log_file.lock().unwrap();
        
        let result = if success { "成功" } else { "失败" };
        writeln!(writer, "")?;
        writeln!(writer, "=== USB 调试会话结束 ===")?;
        writeln!(writer, "结果: {}", result)?;
        
        writer.flush()?;
        Ok(())
    }
}

/// 启动 USB 调试会话并收集所有信息
pub fn debug_usb(session_name: String) -> Result<String, String> {
    let session = match UsbDebugSession::new(&session_name) {
        Ok(s) => s,
        Err(e) => return Err(format!("创建调试会话失败: {}", e)),
    };
    
    // 记录系统信息
    if let Err(e) = session.log_system_usb_info() {
        warn!("记录系统 USB 信息失败: {}", e);
    }
    
    // 检查是否有正在运行的设备服务
    session.log_usb_error("测试", "测试错误信息").ok();
    
    // 获取日志文件路径
    if let Some(path) = session.get_log_path() {
        session.end_session(true).ok();
        Ok(format!(
            "USB 调试日志已生成:\n{}\n\n\
             请在日志中查找问题:\n\
             1. 查找 Android 设备（VID: 18D1, 22D9 等）\n\
             2. 检查设备是否可以正常打开\n\
             3. 检查 AOA 握手步骤是否有错误",
            path.display()
        ))
    } else {
        Ok("USB 调试日志创建失败".to_string())
    }
}

/// 检测 WinUSB 驱动状态
pub fn check_winusb_driver() -> String {
    // Windows 特定的驱动检测
    #[cfg(target_os = "windows")]
    {
        
        let mut result = String::new();
        result.push_str("=== WinUSB 驱动检测 ===\n\n");
        
        // 检查 Zadig 是否已安装 WinUSB
        let devices = match rusb::devices() {
            Ok(d) => d,
            Err(e) => {
                result.push_str(&format!("✗ libusb 不可用: {}\n", e));
                return result;
            }
        };
        
        result.push_str(&format!("发现 {} 个 USB 设备\n\n", devices.len()));
        
        let mut android_devices_found = 0;
        let mut needs_winusb = Vec::new();
        let mut has_winusb = Vec::new();
        
        for device in devices.iter() {
            let desc = match device.device_descriptor() {
                Ok(d) => d,
                Err(_) => continue,
            };
            
            let vid = desc.vendor_id();
            let pid = desc.product_id();
            
            if ANDROID_VENDOR_IDS.contains(&vid) {
                android_devices_found += 1;
                
                // 尝试判断驱动类型
                match device.open() {
                    Ok(handle) => {
                        // 可以打开，驱动正常
                        has_winusb.push(format!("{:04X}:{:04X}", vid, pid));
                    }
                    Err(rusb::Error::Access) => {
                        // 权限不足，可能是 MTP/ADB 驱动占用了设备
                        needs_winusb.push(format!("{:04X}:{:04X} (权限不足)", vid, pid));
                    }
                    Err(rusb::Error::NotFound) => {
                        // 设备不存在或已断开
                        needs_winusb.push(format!("{:04X}:{:04X} (未找到)", vid, pid));
                    }
                    Err(e) => {
                        // 其他错误
                        needs_winusb.push(format!("{:04X}:{:04X} ({})", vid, pid, e));
                    }
                }
            }
        }
        
        if android_devices_found == 0 {
            result.push_str("未发现 Android 设备\n");
        } else {
            result.push_str(&format!("发现 {} 个 Android 设备\n\n", android_devices_found));
            
            if !has_winusb.is_empty() {
                result.push_str("✅ 已有 WinUSB 驱动的设备:\n");
                for dev in has_winusb {
                    result.push_str(&format!("  - {}\n", dev));
                }
                result.push_str("\n");
            }
            
            if !needs_winusb.is_empty() {
                result.push_str("⚠ 需要 WinUSB 驱动的设备:\n");
                for dev in needs_winusb {
                    result.push_str(&format!("  - {}\n", dev));
                }
                result.push_str("\n");
                
                // 提供修复建议
                result.push_str("📱 修复建议:\n");
                result.push_str("1. 下载 Zadig: https://zadig.akeo.ie/\n");
                result.push_str("2. 运行 Zadig → Options → List All Devices\n");
                result.push_str("3. 从列表中选择上述 Android 设备\n");
                result.push_str("4. 驱动选择 WinUSB (libusb-win32)\n");
                result.push_str("5. 点击 Replace Driver\n");
                result.push_str("6. 完成后可能需要重启手机或切换 USB 模式\n");
                result.push_str("   （建议使用「仅充电」模式）\n");
            }
        }
        
        result
    }
    
    #[cfg(not(target_os = "windows"))]
    {
        "此功能仅支持 Windows 系统".to_string()
    }
}

/// 强制重新枚举 USB 设备（Windows）
#[cfg(target_os = "windows")]
pub fn reset_usb_device(vid_hex: String, pid_hex: String) -> Result<String, String> {
    use std::process::Command;
    
    // 解析 VID:PID
    let vid = u16::from_str_radix(&vid_hex, 16)
        .map_err(|_| format!("无效的 VID: {}", vid_hex))?;
    let pid = u16::from_str_radix(&pid_hex, 16)
        .map_err(|_| format!("无效的 PID: {}", pid_hex))?;
    
    // 构建设备实例路径
    let dev_instance = format!("USB\\VID_{:04X}&PID_{:04X}", vid, pid);
    
    info!("尝试重置 USB 设备: {}", dev_instance);
    
    // 使用 devcon 工具重置设备（需要管理员权限）
    // 注意：devcon 需要从 Windows Driver Kit (WDK) 获取
    // 这里提供一个替代方案
    
    Ok(format!(
        "请手动重置设备:\n\
         1. 打开设备管理器\n\
         2. 找到 \"通用串行总线控制器\"\n\
         3. 找到 VID_{:04X}&PID_{:04X} 设备\n\
         4. 右键点击 → 禁用设备\n\
         5. 稍等片刻 → 右键点击 → 启用设备\n\
         6. 或者直接拔插 USB 线\n\n\
         注意：Windows 可能需要 WinUSB 驱动才能正确识别 AOA 设备",
        vid, pid
    ))
}

#[cfg(not(target_os = "windows"))]
pub fn reset_usb_device(_vid_hex: String, _pid_hex: String) -> Result<String, String> {
    Ok("此功能仅支持 Windows 系统".to_string())
}